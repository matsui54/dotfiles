use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::{Mutex, OnceLock};

use fff_search::file_picker::{FFFMode, FilePicker, FilePickerOptions, FuzzySearchOptions};
use fff_search::frecency::FrecencyTracker;
use fff_search::git::format_git_status_opt;
use fff_search::grep::{Casing, GrepMode, GrepSearchOptions};
use fff_search::query_tracker::QueryTracker;
use fff_search::types::PaginationArgs;
use fff_search::{
    FuzzyQuery, GrepConfig, Location, QueryParser, SharedFilePicker, SharedFrecency,
    SharedQueryTracker,
};
use frizbee::{Config as FrizbeeConfig, Matcher as FrizbeeMatcher, Pattern as FrizbeePattern};
use mlua::prelude::*;

mod git_log;

const DEFAULT_LIMIT: usize = 200;
const DEFAULT_MAX_MATCHES_PER_FILE: usize = 50;

struct GlobalState {
    initialized: bool,
    frecency: SharedFrecency,
    query_tracker: SharedQueryTracker,
    pickers: HashMap<PathBuf, SharedFilePicker>,
}

impl GlobalState {
    fn new() -> Self {
        Self {
            initialized: false,
            frecency: SharedFrecency::default(),
            query_tracker: SharedQueryTracker::default(),
            pickers: HashMap::new(),
        }
    }
}

static STATE: OnceLock<Mutex<GlobalState>> = OnceLock::new();

fn global_state() -> &'static Mutex<GlobalState> {
    STATE.get_or_init(|| Mutex::new(GlobalState::new()))
}

fn normalize_path(path: &str) -> PathBuf {
    let p = PathBuf::from(path);
    std::fs::canonicalize(&p).unwrap_or(p)
}

fn ensure_dir_0700(path: &Path) -> std::io::Result<()> {
    std::fs::create_dir_all(path)?;
    #[cfg(unix)]
    {
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(path, std::fs::Permissions::from_mode(0o700))?;
    }
    Ok(())
}

fn ensure_picker_locked(
    state: &mut GlobalState,
    dir: &str,
) -> Result<(PathBuf, SharedFilePicker), String> {
    let canon = normalize_path(dir);
    if let Some(existing) = state.pickers.get(&canon) {
        return Ok((canon, existing.clone()));
    }

    let shared_picker = SharedFilePicker::default();
    let opts = FilePickerOptions {
        base_path: canon.to_string_lossy().into_owned(),
        mode: FFFMode::Neovim,
        enable_mmap_cache: true,
        enable_content_indexing: false,
        watch: true,
        ..Default::default()
    };

    FilePicker::new_with_shared_state(shared_picker.clone(), state.frecency.clone(), opts)
        .map_err(|e| format!("FilePicker init failed for {}: {e}", canon.display()))?;

    state.pickers.insert(canon.clone(), shared_picker.clone());
    Ok((canon, shared_picker))
}

fn get_or_create_picker(
    dir: &str,
) -> Result<(PathBuf, SharedFilePicker, SharedQueryTracker), String> {
    let mut state = global_state()
        .lock()
        .map_err(|_| "GlobalState mutex poisoned".to_string())?;
    let (canon, picker) = ensure_picker_locked(&mut state, dir)?;
    let qt = state.query_tracker.clone();
    Ok((canon, picker, qt))
}

struct ScanStatusOut {
    scanning: bool,
    total_files: usize,
}

fn scan_status_impl(dir: &str) -> Result<ScanStatusOut, String> {
    let canon = normalize_path(dir);
    let sp = {
        let state = global_state()
            .lock()
            .map_err(|_| "GlobalState mutex poisoned".to_string())?;
        state.pickers.get(&canon).cloned()
    };

    let Some(sp) = sp else {
        return Ok(ScanStatusOut {
            scanning: false,
            total_files: 0,
        });
    };

    let guard = sp.read().map_err(|e| format!("Picker lock error: {e}"))?;
    let Some(picker) = guard.as_ref() else {
        return Ok(ScanStatusOut {
            scanning: true,
            total_files: 0,
        });
    };

    let progress = picker.get_scan_progress();
    let live = picker.live_file_count();
    let total_files = if progress.is_scanning {
        progress.scanned_files_count.max(live)
    } else {
        live
    };

    Ok(ScanStatusOut {
        scanning: progress.is_scanning,
        total_files,
    })
}

struct FileMatchOut {
    path: String,
    rel_path: String,
    score: i32,
    match_indices: Vec<u32>,
    git_status: Option<&'static str>,
    size: u64,
}

struct SearchFilesOut {
    items: Vec<FileMatchOut>,
    total_matched: usize,
    total_files: usize,
    scanning: bool,
    loc_lnum: Option<i32>,
    loc_col: Option<i32>,
}

fn collect_single_char_indices(query: &FuzzyQuery<'_>, rel_path: &str) -> Vec<u32> {
    let needle = match query {
        FuzzyQuery::Text(t) if !t.is_empty() => *t,
        FuzzyQuery::Parts(parts) => match parts.first() {
            Some(p) if !p.is_empty() => *p,
            _ => return Vec::new(),
        },
        _ => return Vec::new(),
    };

    let cfg = FrizbeeConfig::default();
    let mut matcher = FrizbeeMatcher::new(needle, &cfg);
    let mut matched = matcher.match_list_indices(&[rel_path]);
    if let Some(first) = matched.pop() {
        let mut indices = first.indices;
        indices.sort_unstable();
        indices.dedup();
        indices
    } else {
        Vec::new()
    }
}

fn search_files_with_picker(
    picker: &FilePicker,
    query_tracker: Option<&QueryTracker>,
    query: &str,
    limit: usize,
    current_file: Option<&str>,
) -> SearchFilesOut {
    let parser = QueryParser::default();
    let parsed = parser.parse(query);

    let results = picker.fuzzy_search(
        &parsed,
        query_tracker,
        FuzzySearchOptions {
            max_threads: 0,
            current_file,
            project_path: Some(picker.base_path()),
            combo_boost_score_multiplier: 100,
            min_combo_count: 3,
            pagination: PaginationArgs { offset: 0, limit },
        },
    );

    let (loc_lnum, loc_col) = match results.location {
        Some(Location::Line(l)) => (Some(l), None),
        Some(Location::Position { line, col }) => (Some(line), Some(col)),
        Some(Location::Range { start, .. }) => (Some(start.0), Some(start.1)),
        None => (None, None),
    };

    let mut items = Vec::with_capacity(results.items.len());
    for (idx, file) in results.items.iter().enumerate() {
        let rel_path = file.relative_path(picker);
        let abs_path = file
            .absolute_path(picker, picker.base_path())
            .to_string_lossy()
            .into_owned();
        let score = results.scores.get(idx).map(|s| s.total).unwrap_or(0);
        let git_status = format_git_status_opt(file.git_status);

        let mut match_indices = Vec::new();
        if let Some(ranges) = results.match_byte_offsets.get(idx) {
            for &(start, end) in ranges {
                for b in start..end {
                    match_indices.push(b);
                }
            }
        }
        if match_indices.is_empty() && !matches!(parsed.fuzzy_query, FuzzyQuery::Empty) {
            match_indices = collect_single_char_indices(&parsed.fuzzy_query, &rel_path);
        } else {
            match_indices.sort_unstable();
            match_indices.dedup();
        }

        items.push(FileMatchOut {
            path: abs_path,
            rel_path,
            score,
            match_indices,
            git_status,
            size: file.size,
        });
    }

    SearchFilesOut {
        items,
        total_matched: results.total_matched,
        total_files: results.total_files,
        scanning: picker.is_scan_active(),
        loc_lnum,
        loc_col,
    }
}

fn search_files_impl(
    dir: &str,
    query: &str,
    limit: usize,
    current_file: Option<&str>,
) -> Result<SearchFilesOut, String> {
    let (_canon, sp, sqt) = get_or_create_picker(dir)?;
    let guard = sp.read().map_err(|e| format!("Picker lock error: {e}"))?;
    let Some(picker) = guard.as_ref() else {
        return Ok(SearchFilesOut {
            items: Vec::new(),
            total_matched: 0,
            total_files: 0,
            scanning: true,
            loc_lnum: None,
            loc_col: None,
        });
    };

    let qt_guard = sqt
        .read()
        .map_err(|e| format!("QueryTracker lock error: {e}"))?;
    Ok(search_files_with_picker(
        picker,
        qt_guard.as_ref(),
        query,
        limit,
        current_file,
    ))
}

struct GrepMatchOut {
    path: String,
    rel_path: String,
    lnum: u64,
    col: usize,
    end_col: usize,
    text: String,
    match_ranges: Vec<(u32, u32)>,
}

struct LiveGrepOut {
    items: Vec<GrepMatchOut>,
    total_matched: usize,
    total_files: usize,
    has_more: bool,
    scanning: bool,
}

fn live_grep_with_picker(
    picker: &FilePicker,
    query: &str,
    limit: usize,
    max_per_file: usize,
) -> LiveGrepOut {
    if query.trim().is_empty() {
        return LiveGrepOut {
            items: Vec::new(),
            total_matched: 0,
            total_files: picker.live_file_count(),
            has_more: false,
            scanning: picker.is_scan_active(),
        };
    }

    let parser = QueryParser::new(GrepConfig);
    let parsed = parser.parse(query);
    let opts = GrepSearchOptions {
        mode: GrepMode::PlainText,
        page_limit: limit,
        max_matches_per_file: max_per_file,
        smart_case: true,
        casing: Some(Casing::Smart),
        trim_whitespace: false,
        ..Default::default()
    };

    let res = picker.grep(&parsed, &opts);
    let total_matched = res.matches.len();
    let mut items = Vec::with_capacity(res.matches.len().min(limit));

    for m in res.matches.into_iter().take(limit) {
        let Some(file) = res.files.get(m.file_index) else {
            continue;
        };
        let rel_path = file.relative_path(picker);
        let abs_path = file
            .absolute_path(picker, picker.base_path())
            .to_string_lossy()
            .into_owned();
        let end_col = m
            .match_byte_offsets
            .first()
            .map(|r| r.1 as usize)
            .unwrap_or(m.col);
        let match_ranges = m.match_byte_offsets.into_vec();

        items.push(GrepMatchOut {
            path: abs_path,
            rel_path,
            lnum: m.line_number,
            col: m.col,
            end_col,
            text: m.line_content,
            match_ranges,
        });
    }

    LiveGrepOut {
        items,
        total_matched,
        total_files: res.total_files,
        has_more: res.next_file_offset > 0,
        scanning: picker.is_scan_active(),
    }
}

fn live_grep_impl(
    dir: &str,
    query: &str,
    limit: usize,
    max_per_file: usize,
) -> Result<LiveGrepOut, String> {
    let (_canon, sp, _sqt) = get_or_create_picker(dir)?;
    let guard = sp.read().map_err(|e| format!("Picker lock error: {e}"))?;
    let Some(picker) = guard.as_ref() else {
        return Ok(LiveGrepOut {
            items: Vec::new(),
            total_matched: 0,
            total_files: 0,
            has_more: false,
            scanning: true,
        });
    };

    Ok(live_grep_with_picker(picker, query, limit, max_per_file))
}

struct FuzzyListItemOut {
    idx: usize,
    score: u16,
    match_indices: Vec<u32>,
}

struct FuzzyListOut {
    items: Vec<FuzzyListItemOut>,
    total_matched: usize,
    total_items: usize,
}

fn fuzzy_match_list_impl(query: &str, items: &[String], limit: usize) -> FuzzyListOut {
    let total_items = items.len();
    let trimmed = query.trim();

    if trimmed.is_empty() {
        let count = limit.min(total_items);
        let out = (0..count)
            .map(|i| FuzzyListItemOut {
                idx: i + 1,
                score: 0,
                match_indices: Vec::new(),
            })
            .collect();
        return FuzzyListOut {
            items: out,
            total_matched: total_items,
            total_items,
        };
    }

    let patterns: Vec<FrizbeePattern> = FrizbeePattern::parse_query(trimmed)
        .into_iter()
        .map(|p| {
            let max_typos = (p.needle.len() / 4) as u16;
            p.max_typos(Some(max_typos))
        })
        .collect();

    let cfg = FrizbeeConfig::default();
    let mut matcher = FrizbeeMatcher::from_patterns(&patterns, &cfg);
    let matches = matcher.match_list(items);
    let total_matched = matches.len();

    let mut out = Vec::with_capacity(limit.min(total_matched));
    for m in matches.into_iter().take(limit) {
        let idx_0 = m.index as usize;
        let mut indices = Vec::new();
        if let Some(haystack) = items.get(idx_0) {
            let mut matched = matcher.match_list_indices(&[haystack.as_str()]);
            if let Some(first) = matched.pop() {
                indices = first.indices;
                indices.sort_unstable();
                indices.dedup();
            }
        }
        out.push(FuzzyListItemOut {
            idx: idx_0 + 1,
            score: m.score,
            match_indices: indices,
        });
    }

    FuzzyListOut {
        items: out,
        total_matched,
        total_items,
    }
}

fn track_access_impl(path: &str) -> Result<(), String> {
    let target = normalize_path(path);
    let (frecency, pickers) = {
        let state = global_state()
            .lock()
            .map_err(|_| "GlobalState mutex poisoned".to_string())?;
        let pickers: Vec<SharedFilePicker> = state.pickers.values().cloned().collect();
        (state.frecency.clone(), pickers)
    };

    let guard = frecency
        .read()
        .map_err(|e| format!("Frecency lock error: {e}"))?;
    let Some(tracker) = guard.as_ref() else {
        return Ok(());
    };

    tracker
        .track_access(&target)
        .map_err(|e| format!("track_access failed: {e}"))?;

    for sp in pickers {
        if let Ok(mut picker_guard) = sp.write() {
            if let Some(picker) = picker_guard.as_mut() {
                if target.starts_with(picker.base_path()) {
                    let _ = picker.update_single_file_frecency(&target, tracker);
                }
            }
        }
    }

    Ok(())
}

fn track_query_impl(dir: &str, query: &str, path: &str) -> Result<(), String> {
    if query.trim().is_empty() {
        return Ok(());
    }
    let canon_dir = normalize_path(dir);
    let canon_path = normalize_path(path);

    let sqt = {
        let state = global_state()
            .lock()
            .map_err(|_| "GlobalState mutex poisoned".to_string())?;
        state.query_tracker.clone()
    };

    let mut guard = sqt
        .write()
        .map_err(|e| format!("QueryTracker lock error: {e}"))?;
    if let Some(tracker) = guard.as_mut() {
        tracker
            .track_query_completion(query, &canon_dir, &canon_path)
            .map_err(|e| format!("track_query_completion failed: {e}"))?;
    }

    Ok(())
}

fn init_impl(state_dir: Option<&str>, base_path: Option<&str>) -> Result<(), String> {
    let mut state = global_state()
        .lock()
        .map_err(|_| "GlobalState mutex poisoned".to_string())?;

    if !state.initialized {
        if let Some(dir_str) = state_dir.filter(|s| !s.is_empty()) {
            let root = PathBuf::from(dir_str);
            ensure_dir_0700(&root)
                .map_err(|e| format!("Failed to create state_dir {}: {e}", root.display()))?;

            let frecency_dir = root.join("frecency");
            let queries_dir = root.join("queries");

            let frecency = FrecencyTracker::open(&frecency_dir)
                .map_err(|e| format!("Failed to open FrecencyTracker: {e}"))?;
            state
                .frecency
                .init(frecency)
                .map_err(|e| format!("Failed to init SharedFrecency: {e}"))?;

            let qt = QueryTracker::open(&queries_dir)
                .map_err(|e| format!("Failed to open QueryTracker: {e}"))?;
            state
                .query_tracker
                .init(qt)
                .map_err(|e| format!("Failed to init SharedQueryTracker: {e}"))?;
        }
        state.initialized = true;
    }

    if let Some(bp) = base_path.filter(|s| !s.is_empty()) {
        let _ = ensure_picker_locked(&mut state, bp)?;
    }

    Ok(())
}

fn lua_init(_lua: &Lua, opts: Option<LuaTable>) -> LuaResult<bool> {
    let (state_dir, base_path) = match opts {
        Some(t) => {
            let sd: Option<String> = t.get("state_dir")?;
            let bp: Option<String> = t.get("base_path")?;
            (sd, bp)
        }
        None => (None, None),
    };

    init_impl(state_dir.as_deref(), base_path.as_deref()).map_err(LuaError::external)?;
    Ok(true)
}

fn lua_ensure_dir(_lua: &Lua, dir: String) -> LuaResult<String> {
    let (canon, _, _) = get_or_create_picker(&dir).map_err(LuaError::external)?;
    Ok(canon.to_string_lossy().into_owned())
}

fn lua_scan_status(lua: &Lua, dir: String) -> LuaResult<LuaTable> {
    let status = scan_status_impl(&dir).map_err(LuaError::external)?;
    let tbl = lua.create_table()?;
    tbl.set("scanning", status.scanning)?;
    tbl.set("total_files", status.total_files)?;
    Ok(tbl)
}

fn lua_search_files(
    lua: &Lua,
    (dir, query, opts): (String, String, Option<LuaTable>),
) -> LuaResult<LuaTable> {
    let mut limit = DEFAULT_LIMIT;
    let mut current_file: Option<String> = None;
    if let Some(t) = opts {
        if let Some(l) = t.get::<Option<usize>>("limit")? {
            limit = l.max(1);
        }
        current_file = t.get::<Option<String>>("current_file")?;
    }

    let out = search_files_impl(&dir, &query, limit, current_file.as_deref())
        .map_err(LuaError::external)?;

    let tbl = lua.create_table()?;
    let lua_items = lua.create_table_with_capacity(out.items.len(), 0)?;
    for (idx, item) in out.items.into_iter().enumerate() {
        let row = lua.create_table()?;
        row.set("path", item.path)?;
        row.set("rel_path", item.rel_path)?;
        row.set("score", item.score)?;
        row.set("size", item.size)?;
        if let Some(gs) = item.git_status {
            row.set("git_status", gs)?;
        }
        let indices_tbl = lua.create_table_with_capacity(item.match_indices.len(), 0)?;
        for (i, pos) in item.match_indices.into_iter().enumerate() {
            indices_tbl.set(i + 1, pos)?;
        }
        row.set("match_indices", indices_tbl)?;
        lua_items.set(idx + 1, row)?;
    }

    tbl.set("items", lua_items)?;
    tbl.set("total_matched", out.total_matched)?;
    tbl.set("total_files", out.total_files)?;
    tbl.set("scanning", out.scanning)?;
    if let Some(lnum) = out.loc_lnum {
        tbl.set("loc_lnum", lnum)?;
    }
    if let Some(col) = out.loc_col {
        tbl.set("loc_col", col)?;
    }
    Ok(tbl)
}

fn lua_live_grep(
    lua: &Lua,
    (dir, query, opts): (String, String, Option<LuaTable>),
) -> LuaResult<LuaTable> {
    let mut limit = DEFAULT_LIMIT;
    let mut max_per_file = DEFAULT_MAX_MATCHES_PER_FILE;
    if let Some(t) = opts {
        if let Some(l) = t.get::<Option<usize>>("limit")? {
            limit = l.max(1);
        }
        if let Some(m) = t.get::<Option<usize>>("max_matches_per_file")? {
            max_per_file = m.max(1);
        }
    }

    let out = live_grep_impl(&dir, &query, limit, max_per_file).map_err(LuaError::external)?;

    let tbl = lua.create_table()?;
    let lua_items = lua.create_table_with_capacity(out.items.len(), 0)?;
    for (idx, item) in out.items.into_iter().enumerate() {
        let row = lua.create_table()?;
        row.set("path", item.path)?;
        row.set("rel_path", item.rel_path)?;
        row.set("lnum", item.lnum)?;
        row.set("col", item.col)?;
        row.set("end_col", item.end_col)?;
        row.set("text", item.text)?;

        let ranges_tbl = lua.create_table_with_capacity(item.match_ranges.len(), 0)?;
        for (i, (start, end)) in item.match_ranges.into_iter().enumerate() {
            let pair = lua.create_table_with_capacity(2, 0)?;
            pair.set(1, start)?;
            pair.set(2, end)?;
            ranges_tbl.set(i + 1, pair)?;
        }
        row.set("match_ranges", ranges_tbl)?;
        lua_items.set(idx + 1, row)?;
    }

    tbl.set("items", lua_items)?;
    tbl.set("total_matched", out.total_matched)?;
    tbl.set("total_files", out.total_files)?;
    tbl.set("has_more", out.has_more)?;
    tbl.set("scanning", out.scanning)?;
    Ok(tbl)
}

fn lua_track_access(_lua: &Lua, path: String) -> LuaResult<bool> {
    track_access_impl(&path).map_err(LuaError::external)?;
    Ok(true)
}

fn lua_track_query(_lua: &Lua, (dir, query, path): (String, String, String)) -> LuaResult<bool> {
    track_query_impl(&dir, &query, &path).map_err(LuaError::external)?;
    Ok(true)
}

fn lua_fuzzy_match_list(
    lua: &Lua,
    (query, items, opts): (String, Vec<String>, Option<LuaTable>),
) -> LuaResult<LuaTable> {
    let mut limit = DEFAULT_LIMIT;
    if let Some(t) = opts {
        if let Some(l) = t.get::<Option<usize>>("limit")? {
            limit = l.max(1);
        }
    }

    let out = fuzzy_match_list_impl(&query, &items, limit);
    let tbl = lua.create_table()?;
    let lua_items = lua.create_table_with_capacity(out.items.len(), 0)?;

    for (idx, item) in out.items.into_iter().enumerate() {
        let row = lua.create_table()?;
        row.set("idx", item.idx)?;
        row.set("score", item.score)?;
        let indices_tbl = lua.create_table_with_capacity(item.match_indices.len(), 0)?;
        for (i, pos) in item.match_indices.into_iter().enumerate() {
            indices_tbl.set(i + 1, pos)?;
        }
        row.set("match_indices", indices_tbl)?;
        lua_items.set(idx + 1, row)?;
    }

    tbl.set("items", lua_items)?;
    tbl.set("total_matched", out.total_matched)?;
    tbl.set("total_items", out.total_items)?;
    Ok(tbl)
}

fn lua_git_log_open(lua: &Lua, opts: LuaTable) -> LuaResult<LuaTable> {
    let root: String = opts.get("root")?;
    let filter_file = opts
        .get::<Option<String>>("filter_file")?
        .filter(|s| !s.is_empty());
    let line_range = match opts.get::<Option<LuaTable>>("line_range")? {
        Some(t) => {
            let l1 = t.get::<Option<u32>>(1)?;
            let l2 = t.get::<Option<u32>>(2)?;
            match (l1, l2) {
                (Some(a), Some(b)) => Some((a, b)),
                _ => None,
            }
        }
        None => None,
    };
    let explicit_limit = opts.get::<Option<usize>>("limit")?;
    let force = opts.get::<Option<bool>>("force")?.unwrap_or(false);

    let out = git_log::open_session(&root, filter_file, line_range, explicit_limit, force)
        .map_err(LuaError::external)?;

    let tbl = lua.create_table()?;
    tbl.set("session_id", out.session_id)?;
    tbl.set("branch", out.branch)?;
    tbl.set("head_oid", out.head_oid)?;
    tbl.set("cached", out.cached)?;
    tbl.set("scanning", out.scanning)?;
    tbl.set("total_items", out.total_items)?;
    tbl.set("has_more", out.has_more)?;
    tbl.set("revision", out.revision)?;
    Ok(tbl)
}

fn lua_git_log_status(lua: &Lua, session_id: u64) -> LuaResult<LuaTable> {
    let st = git_log::session_status(session_id).map_err(LuaError::external)?;
    let tbl = lua.create_table()?;
    tbl.set("exists", st.exists)?;
    tbl.set("scanning", st.scanning)?;
    tbl.set("total_items", st.total_items)?;
    tbl.set("has_more", st.has_more)?;
    tbl.set("revision", st.revision)?;
    if let Some(err) = st.error {
        tbl.set("error", err)?;
    }
    Ok(tbl)
}

fn lua_git_log_search(
    lua: &Lua,
    (session_id, query, opts): (u64, String, Option<LuaTable>),
) -> LuaResult<LuaTable> {
    let mut limit = DEFAULT_LIMIT;
    let mut offset = 0usize;
    if let Some(t) = opts {
        if let Some(l) = t.get::<Option<usize>>("limit")? {
            limit = l.max(1);
        }
        if let Some(o) = t.get::<Option<usize>>("offset")? {
            offset = o;
        }
    }

    let out = git_log::search_session(session_id, &query, limit, offset)
        .map_err(LuaError::external)?;

    let tbl = lua.create_table()?;
    let lua_items = lua.create_table_with_capacity(out.items.len(), 0)?;
    for (idx, item) in out.items.into_iter().enumerate() {
        let row = lua.create_table()?;
        row.set("order_idx", item.order_idx)?;
        row.set("hash", item.hash.as_ref())?;
        row.set("short", item.short.as_ref())?;
        row.set("display", item.display.as_ref())?;
        row.set("short_len", item.short_len)?;
        row.set("date_start", item.date_start)?;
        row.set("date_end", item.date_end)?;
        row.set("author_start", item.author_start)?;
        row.set("author_end", item.author_end)?;
        row.set("refs_start", item.refs_start)?;
        row.set("refs_end", item.refs_end)?;
        row.set("has_parent", item.has_parent)?;
        row.set("score", item.score)?;

        let indices_tbl = lua.create_table_with_capacity(item.match_indices.len(), 0)?;
        for (i, pos) in item.match_indices.into_iter().enumerate() {
            indices_tbl.set(i + 1, pos)?;
        }
        row.set("match_indices", indices_tbl)?;
        lua_items.set(idx + 1, row)?;
    }

    tbl.set("exists", out.exists)?;
    tbl.set("items", lua_items)?;
    tbl.set("total_matched", out.total_matched)?;
    tbl.set("total_items", out.total_items)?;
    tbl.set("scanning", out.scanning)?;
    tbl.set("has_more", out.has_more)?;
    tbl.set("revision", out.revision)?;
    if let Some(err) = out.error {
        tbl.set("error", err)?;
    }
    Ok(tbl)
}

fn lua_git_log_load_more(
    lua: &Lua,
    (session_id, add_count): (u64, Option<usize>),
) -> LuaResult<LuaTable> {
    let out = git_log::load_more(session_id, add_count.unwrap_or(git_log::DEFAULT_MAX_COMMITS))
        .map_err(LuaError::external)?;
    let tbl = lua.create_table()?;
    tbl.set("started", out.started)?;
    tbl.set("queued", out.queued)?;
    tbl.set("already_complete", out.already_complete)?;
    tbl.set("total_items", out.total_items)?;
    tbl.set("max_commits", out.max_commits)?;
    Ok(tbl)
}

fn lua_git_log_cancel(
    _lua: &Lua,
    (session_id, opts): (u64, Option<LuaTable>),
) -> LuaResult<bool> {
    let only_if_scanning = match opts {
        Some(t) => t.get::<Option<bool>>("only_if_scanning")?.unwrap_or(false),
        None => false,
    };
    git_log::cancel_session(session_id, only_if_scanning).map_err(LuaError::external)
}

#[mlua::lua_module]
fn my_finder_native(lua: &Lua) -> LuaResult<LuaTable> {
    let exports = lua.create_table()?;
    exports.set("init", lua.create_function(lua_init)?)?;
    exports.set("ensure_dir", lua.create_function(lua_ensure_dir)?)?;
    exports.set("scan_status", lua.create_function(lua_scan_status)?)?;
    exports.set("search_files", lua.create_function(lua_search_files)?)?;
    exports.set("live_grep", lua.create_function(lua_live_grep)?)?;
    exports.set("track_access", lua.create_function(lua_track_access)?)?;
    exports.set("track_query", lua.create_function(lua_track_query)?)?;
    exports.set(
        "fuzzy_match_list",
        lua.create_function(lua_fuzzy_match_list)?,
    )?;
    exports.set("git_log_open", lua.create_function(lua_git_log_open)?)?;
    exports.set("git_log_status", lua.create_function(lua_git_log_status)?)?;
    exports.set("git_log_search", lua.create_function(lua_git_log_search)?)?;
    exports.set(
        "git_log_load_more",
        lua.create_function(lua_git_log_load_more)?,
    )?;
    exports.set("git_log_cancel", lua.create_function(lua_git_log_cancel)?)?;
    Ok(exports)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::Duration;

    #[test]
    fn fuzzy_match_list_empty_query_preserves_order_and_respects_limit() {
        let items = vec![
            "alpha".to_string(),
            "beta".to_string(),
            "gamma".to_string(),
            "delta".to_string(),
        ];
        let res = fuzzy_match_list_impl("", &items, 2);
        assert_eq!(res.total_items, 4);
        assert_eq!(res.total_matched, 4);
        assert_eq!(res.items.len(), 2);
        assert_eq!(res.items[0].idx, 1);
        assert_eq!(res.items[1].idx, 2);
        assert!(res.items[0].match_indices.is_empty());
    }

    #[test]
    fn fuzzy_match_list_matches_typo_tolerant_and_utf8_byte_indices() {
        let items = vec![
            "nvim/lua/plugins/picker.lua".to_string(),
            "日本語テスト/picker.lua".to_string(),
            "scripts/pkglib.py".to_string(),
        ];
        let res = fuzzy_match_list_impl("piker", &items, 10);
        assert_eq!(res.total_matched, 2);
        let matched_indices: Vec<usize> = res.items.iter().map(|m| m.idx).collect();
        assert!(matched_indices.contains(&1));
        assert!(matched_indices.contains(&2));
        for item in &res.items {
            assert!(!item.match_indices.is_empty());
            let hay = &items[item.idx - 1];
            for &b in &item.match_indices {
                assert!((b as usize) < hay.len());
            }
        }
    }

    #[test]
    fn fff_search_indexes_searches_and_greps_dotfiles_repo() {
        let repo_root = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(5)
            .expect("dotfiles root")
            .to_path_buf();

        let shared_picker = SharedFilePicker::default();
        let shared_frecency = SharedFrecency::default();
        let opts = FilePickerOptions {
            base_path: repo_root.to_string_lossy().into_owned(),
            mode: FFFMode::Neovim,
            enable_mmap_cache: false,
            enable_content_indexing: false,
            watch: false,
            ..Default::default()
        };

        FilePicker::new_with_shared_state(shared_picker.clone(), shared_frecency, opts)
            .expect("create FilePicker");
        assert!(
            shared_picker.wait_for_scan(Duration::from_secs(10)),
            "scan timed out"
        );

        let guard = shared_picker.read().expect("read lock");
        let picker = guard.as_ref().expect("picker initialized");
        assert!(picker.live_file_count() > 0);

        let file_res = search_files_with_picker(picker, None, "git_status.lua", 20, None);
        assert!(file_res.total_matched > 0);
        assert!(
            file_res
                .items
                .iter()
                .any(|item| item.rel_path.ends_with("git_status.lua"))
        );

        let empty_grep = live_grep_with_picker(picker, "   ", 20, 10);
        assert_eq!(empty_grep.total_matched, 0);
        assert!(empty_grep.items.is_empty());

        let grep_res = live_grep_with_picker(picker, "parse_status", 20, 10);
        assert!(grep_res.total_matched > 0);
        let hit = grep_res
            .items
            .iter()
            .find(|m| m.rel_path.ends_with("git_status.lua"))
            .expect("expected match in git_status.lua");
        assert!(hit.lnum > 0);
        assert!(!hit.match_ranges.is_empty());
    }
}
