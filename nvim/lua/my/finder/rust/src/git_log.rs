use std::collections::{HashMap, HashSet};
use std::io::{BufRead, BufReader, Read};
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering};
use std::sync::{Arc, Mutex, OnceLock, RwLock};
use std::time::{Duration, Instant};

use frizbee::{Config as FrizbeeConfig, Matcher as FrizbeeMatcher, Pattern as FrizbeePattern};

use crate::normalize_path;

pub const DEFAULT_MAX_COMMITS: usize = 200_000;
const FIRST_FLUSH_COUNT: usize = 200;
const STREAM_BATCH_COUNT: usize = 2048;
const STREAM_FLUSH_INTERVAL: Duration = Duration::from_millis(60);
const MAX_CACHED_SESSIONS: usize = 3;
const PIPE_BUF_CAPACITY: usize = 64 * 1024;

#[derive(Clone, Debug, PartialEq, Eq, Hash)]
pub struct GitLogKey {
    pub git_root: PathBuf,
    pub filter_file: Option<String>,
    pub line_range: Option<(u32, u32)>,
}

#[derive(Clone, Debug)]
pub struct CommitEntry {
    pub hash: Box<str>,
    pub display: Box<str>,
    pub short_len: u16,
    pub date_start: u16,
    pub date_end: u16,
    pub author_start: u16,
    pub author_end: u16,
    pub refs_start: u16,
    pub refs_end: u16,
    pub has_parent: bool,
}

impl CommitEntry {
    pub fn short(&self) -> &str {
        let len = (self.short_len as usize).min(self.display.len());
        if self.display.is_char_boundary(len) {
            &self.display[..len]
        } else {
            &self.display
        }
    }
}

impl AsRef<str> for CommitEntry {
    fn as_ref(&self) -> &str {
        &self.display
    }
}

pub fn parse_commit_record(raw: &[u8]) -> Option<CommitEntry> {
    let trimmed_raw = raw.strip_suffix(b"\x1e").unwrap_or(raw);
    let text = String::from_utf8_lossy(trimmed_raw);
    let mut fields = text.split('\0');

    let hash = fields.next()?.trim();
    if hash.is_empty() {
        return None;
    }
    let short = fields.next()?;
    let date = fields.next()?;
    let author = fields.next()?;
    let refs = fields.next()?.trim();
    let subject = fields.next()?;
    let parents = fields.next().map(str::trim).unwrap_or("");

    let has_refs = !refs.is_empty();
    let display = if has_refs {
        format!("{short}  {date}  {author} {refs}  {subject}")
    } else {
        format!("{short}  {date}  {author}  {subject}")
    };

    let clamp_u16 = |n: usize| -> u16 { n.min(u16::MAX as usize) as u16 };
    let short_len = short.len();
    let date_start = short_len + 2;
    let date_end = date_start + date.len();
    let author_start = date_end + 2;
    let author_end = author_start + author.len();
    let (refs_start, refs_end) = if has_refs {
        let rs = author_end + 1;
        (rs, rs + refs.len())
    } else {
        (0, 0)
    };

    Some(CommitEntry {
        hash: hash.into(),
        display: display.into_boxed_str(),
        short_len: clamp_u16(short_len),
        date_start: clamp_u16(date_start),
        date_end: clamp_u16(date_end),
        author_start: clamp_u16(author_start),
        author_end: clamp_u16(author_end),
        refs_start: clamp_u16(refs_start),
        refs_end: clamp_u16(refs_end),
        has_parent: !parents.is_empty(),
    })
}

pub struct GitLogSession {
    pub id: u64,
    pub key: GitLogKey,
    pub head_oid: String,
    pub branch: String,
    pub explicit_limit: Option<usize>,
    pub commits: RwLock<Vec<CommitEntry>>,
    pub count: AtomicUsize,
    pub scanning: AtomicBool,
    pub has_more: AtomicBool,
    pub cancelled: AtomicBool,
    pub revision: AtomicU64,
    pub max_commits: AtomicUsize,
    pub error: Mutex<Option<String>>,
    pub active_child: Mutex<Option<Child>>,
    pub last_used: AtomicU64,
}

impl GitLogSession {
    fn kill_child(&self) {
        if let Ok(mut guard) = self.active_child.lock() {
            if let Some(child) = guard.as_mut() {
                let _ = child.kill();
            }
        }
    }
}

struct GitLogManager {
    next_id: u64,
    use_clock: u64,
    sessions: HashMap<u64, Arc<GitLogSession>>,
}

impl GitLogManager {
    fn new() -> Self {
        Self {
            next_id: 0,
            use_clock: 0,
            sessions: HashMap::new(),
        }
    }
}

static MANAGER: OnceLock<Mutex<GitLogManager>> = OnceLock::new();

fn manager() -> &'static Mutex<GitLogManager> {
    MANAGER.get_or_init(|| Mutex::new(GitLogManager::new()))
}

pub struct GitLogOpenOut {
    pub session_id: u64,
    pub branch: String,
    pub head_oid: String,
    pub cached: bool,
    pub scanning: bool,
    pub total_items: usize,
    pub has_more: bool,
    pub revision: u64,
}

pub struct GitLogStatusOut {
    pub exists: bool,
    pub scanning: bool,
    pub total_items: usize,
    pub has_more: bool,
    pub revision: u64,
    pub error: Option<String>,
}

pub struct GitLogSearchItemOut {
    pub order_idx: usize,
    pub hash: Box<str>,
    pub short: Box<str>,
    pub display: Box<str>,
    pub short_len: u16,
    pub date_start: u16,
    pub date_end: u16,
    pub author_start: u16,
    pub author_end: u16,
    pub refs_start: u16,
    pub refs_end: u16,
    pub has_parent: bool,
    pub score: u16,
    pub match_indices: Vec<u32>,
}

pub struct GitLogSearchOut {
    pub exists: bool,
    pub items: Vec<GitLogSearchItemOut>,
    pub total_matched: usize,
    pub total_items: usize,
    pub scanning: bool,
    pub has_more: bool,
    pub revision: u64,
    pub error: Option<String>,
}

pub struct GitLogLoadMoreOut {
    pub started: bool,
    pub queued: bool,
    pub already_complete: bool,
    pub total_items: usize,
    pub max_commits: usize,
}

fn resolve_head_and_branch(root: &Path) -> (String, String) {
    let output = Command::new("git")
        .arg("-C")
        .arg(root)
        .args(["rev-parse", "HEAD", "--abbrev-ref", "HEAD"])
        .stdin(Stdio::null())
        .output();

    let Ok(out) = output else {
        return (String::new(), "(HEAD)".to_string());
    };
    if !out.status.success() {
        return (String::new(), "(HEAD)".to_string());
    }
    let text = String::from_utf8_lossy(&out.stdout);
    let mut lines = text.lines();
    let head_oid = lines.next().map(str::trim).unwrap_or("").to_string();
    let branch_raw = lines.next().map(str::trim).unwrap_or("");
    let branch = if branch_raw.is_empty() {
        "(HEAD)".to_string()
    } else {
        branch_raw.to_string()
    };
    (head_oid, branch)
}

fn build_item_out(order_idx: usize, entry: &CommitEntry, score: u16, match_indices: Vec<u32>) -> GitLogSearchItemOut {
    GitLogSearchItemOut {
        order_idx,
        hash: entry.hash.clone(),
        short: entry.short().into(),
        display: entry.display.clone(),
        short_len: entry.short_len,
        date_start: entry.date_start,
        date_end: entry.date_end,
        author_start: entry.author_start,
        author_end: entry.author_end,
        refs_start: entry.refs_start,
        refs_end: entry.refs_end,
        has_parent: entry.has_parent,
        score,
        match_indices,
    }
}

fn search_commits_slice(
    commits: &[CommitEntry],
    query: &str,
    limit: usize,
    offset: usize,
) -> (Vec<GitLogSearchItemOut>, usize, usize) {
    let total_items = commits.len();
    let trimmed = query.trim();

    if !trimmed.is_empty() {
        let patterns: Vec<FrizbeePattern> = FrizbeePattern::parse_query(trimmed)
            .into_iter()
            .map(|p| {
                let max_typos = (p.needle.len() / 4) as u16;
                p.max_typos(Some(max_typos))
            })
            .collect();

        if !patterns.is_empty() {
            let cfg = FrizbeeConfig::default();
            let mut matcher = FrizbeeMatcher::from_patterns(&patterns, &cfg);
            let matches = matcher.match_list_parallel(commits, 0);
            let total_matched = matches.len();

            let mut out = Vec::with_capacity(limit.min(total_matched));
            for m in matches.into_iter().skip(offset).take(limit) {
                let idx_0 = m.index as usize;
                let Some(entry) = commits.get(idx_0) else {
                    continue;
                };
                let mut indices = matcher
                    .match_one_indices(&entry.display, m.index)
                    .map(|mi| mi.indices)
                    .unwrap_or_default();
                indices.sort_unstable();
                indices.dedup();
                out.push(build_item_out(idx_0 + 1, entry, m.score, indices));
            }
            return (out, total_matched, total_items);
        }
    }

    let start = offset.min(total_items);
    let end = start.saturating_add(limit).min(total_items);
    let mut out = Vec::with_capacity(end.saturating_sub(start));
    for (idx, entry) in commits[start..end].iter().enumerate() {
        out.push(build_item_out(start + idx + 1, entry, 0, Vec::new()));
    }
    (out, total_items, total_items)
}

fn spawn_worker(session: Arc<GitLogSession>) {
    std::thread::spawn(move || {
        let mut had_error = false;

        loop {
            if session.cancelled.load(Ordering::Acquire) {
                break;
            }

            let target_max = session.max_commits.load(Ordering::SeqCst);
            let current_len = session.count.load(Ordering::Acquire);
            if current_len < target_max {
                let batch_max = target_max - current_len;
                let mut existing_hashes: HashSet<Box<str>> = if current_len > 0 {
                    match session.commits.read() {
                        Ok(guard) => guard.iter().map(|c| c.hash.clone()).collect(),
                        Err(_) => HashSet::new(),
                    }
                } else {
                    HashSet::new()
                };

                let mut cmd = Command::new("git");
                cmd.arg("-C").arg(&session.key.git_root).arg("log");
                if current_len > 0 {
                    cmd.arg(format!("--skip={current_len}"));
                }
                cmd.arg(format!("--max-count={}", batch_max + 1))
                    .arg("--date=short")
                    .arg("--format=%H%x00%h%x00%ad%x00%an%x00%d%x00%s%x00%P%x1e");

                if let Some((l1, l2)) = session.key.line_range {
                    if let Some(ref file) = session.key.filter_file {
                        cmd.arg("--no-patch")
                            .arg(format!("-L{l1},{l2}:{file}"));
                    }
                } else if let Some(ref file) = session.key.filter_file {
                    cmd.arg("--").arg(file);
                }

                cmd.stdin(Stdio::null())
                    .stdout(Stdio::piped())
                    .stderr(Stdio::piped());

                let mut child = match cmd.spawn() {
                    Ok(c) => c,
                    Err(e) => {
                        if !session.cancelled.load(Ordering::Acquire) {
                            if let Ok(mut err_guard) = session.error.lock() {
                                *err_guard = Some(format!("Failed to start git log: {e}"));
                            }
                        }
                        session.has_more.store(false, Ordering::Release);
                        session.scanning.store(false, Ordering::SeqCst);
                        session.revision.fetch_add(1, Ordering::Release);
                        return;
                    }
                };

                let stdout = child.stdout.take();
                let mut stderr = child.stderr.take();
                if let Ok(mut child_guard) = session.active_child.lock() {
                    *child_guard = Some(child);
                }

                let mut batch: Vec<CommitEntry> = Vec::with_capacity(FIRST_FLUSH_COUNT);
                let mut first_flushed = false;
                let mut last_flush = Instant::now();
                let mut batch_received = 0usize;
                let mut saw_more = false;
                let check_dups = current_len > 0;

                if let Some(stdout_pipe) = stdout {
                    let mut reader = BufReader::with_capacity(PIPE_BUF_CAPACITY, stdout_pipe);
                    let mut buf: Vec<u8> = Vec::with_capacity(512);

                    loop {
                        if session.cancelled.load(Ordering::Acquire) {
                            break;
                        }
                        buf.clear();
                        match reader.read_until(b'\x1e', &mut buf) {
                            Ok(0) => break,
                            Ok(_) => {
                                if let Some(entry) = parse_commit_record(&buf) {
                                    batch_received += 1;
                                    if batch_received > batch_max {
                                        saw_more = true;
                                    } else {
                                        let is_dup = check_dups && existing_hashes.contains(&entry.hash);
                                        if !is_dup {
                                            if check_dups {
                                                existing_hashes.insert(entry.hash.clone());
                                            }
                                            batch.push(entry);
                                            let threshold = if !first_flushed {
                                                FIRST_FLUSH_COUNT
                                            } else {
                                                STREAM_BATCH_COUNT
                                            };
                                            if batch.len() >= threshold
                                                || (!batch.is_empty()
                                                    && last_flush.elapsed() >= STREAM_FLUSH_INTERVAL)
                                            {
                                                if let Ok(mut w) = session.commits.write() {
                                                    w.extend(batch.drain(..));
                                                    session.count.store(w.len(), Ordering::Release);
                                                }
                                                session.revision.fetch_add(1, Ordering::Release);
                                                first_flushed = true;
                                                last_flush = Instant::now();
                                            }
                                        }
                                    }
                                }
                            }
                            Err(_) => break,
                        }
                    }
                }

                if !batch.is_empty() && !session.cancelled.load(Ordering::Acquire) {
                    if let Ok(mut w) = session.commits.write() {
                        w.extend(batch.drain(..));
                        session.count.store(w.len(), Ordering::Release);
                    }
                    session.revision.fetch_add(1, Ordering::Release);
                }

                let child_opt = match session.active_child.lock() {
                    Ok(mut g) => g.take(),
                    Err(_) => None,
                };
                if let Some(mut child) = child_opt {
                    let mut err_buf = String::new();
                    if let Some(mut se) = stderr.take() {
                        let _ = se.read_to_string(&mut err_buf);
                    }
                    let status = child.wait();
                    let cancelled = session.cancelled.load(Ordering::Acquire);
                    if !cancelled {
                        let exit_ok = status.map(|s| s.success()).unwrap_or(false);
                        if !exit_ok {
                            had_error = true;
                            let trimmed = err_buf.trim();
                            let msg = if trimmed.is_empty() {
                                "git log failed".to_string()
                            } else {
                                format!("git log failed: {trimmed}")
                            };
                            if let Ok(mut err_guard) = session.error.lock() {
                                *err_guard = Some(msg);
                            }
                        }
                    }
                }

                session.has_more.store(saw_more, Ordering::Release);
                session.revision.fetch_add(1, Ordering::Release);

                if had_error || !saw_more || session.cancelled.load(Ordering::Acquire) {
                    session.scanning.store(false, Ordering::SeqCst);
                    session.revision.fetch_add(1, Ordering::Release);
                    return;
                }
            }

            session.scanning.store(false, Ordering::SeqCst);
            let updated_len = session.count.load(Ordering::SeqCst);
            let updated_target = session.max_commits.load(Ordering::SeqCst);
            let want_more = !session.cancelled.load(Ordering::SeqCst)
                && session.has_more.load(Ordering::SeqCst)
                && !had_error
                && updated_len < updated_target;

            if want_more
                && session
                    .scanning
                    .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
                    .is_ok()
            {
                continue;
            }

            session.revision.fetch_add(1, Ordering::Release);
            return;
        }

        session.scanning.store(false, Ordering::SeqCst);
        session.revision.fetch_add(1, Ordering::Release);
    });
}

pub fn open_session(
    root: &str,
    filter_file: Option<String>,
    line_range: Option<(u32, u32)>,
    explicit_limit: Option<usize>,
    force: bool,
) -> Result<GitLogOpenOut, String> {
    let canon_root = normalize_path(root);
    let key = GitLogKey {
        git_root: canon_root.clone(),
        filter_file,
        line_range,
    };
    let (head_oid, branch) = resolve_head_and_branch(&canon_root);

    let (session_opt, to_spawn) = {
        let mut mgr = manager()
            .lock()
            .map_err(|_| "GitLogManager mutex poisoned".to_string())?;
        mgr.use_clock += 1;
        let now_use = mgr.use_clock;

        if !force && !head_oid.is_empty() {
            let mut hit: Option<Arc<GitLogSession>> = None;
            for s in mgr.sessions.values() {
                if s.key != key || s.head_oid != head_oid || s.cancelled.load(Ordering::Acquire) {
                    continue;
                }
                let has_err = s
                    .error
                    .lock()
                    .ok()
                    .and_then(|g| g.clone())
                    .is_some();
                if has_err {
                    continue;
                }
                let limit_ok = match explicit_limit {
                    None => {
                        s.explicit_limit.is_none()
                            || !s.has_more.load(Ordering::Acquire)
                            || s.max_commits.load(Ordering::Acquire) >= DEFAULT_MAX_COMMITS
                    }
                    Some(req) => s.explicit_limit == Some(req),
                };
                if limit_ok {
                    hit = Some(Arc::clone(s));
                    break;
                }
            }

            if let Some(s) = hit {
                s.last_used.store(now_use, Ordering::Relaxed);
                let total_items = s.commits.read().map(|g| g.len()).unwrap_or(0);
                let scanning = s.scanning.load(Ordering::Acquire);
                let has_more = s.has_more.load(Ordering::Acquire);
                let revision = s.revision.load(Ordering::Acquire);
                return Ok(GitLogOpenOut {
                    session_id: s.id,
                    branch: s.branch.clone(),
                    head_oid: s.head_oid.clone(),
                    cached: true,
                    scanning,
                    total_items,
                    has_more,
                    revision,
                });
            }
        }

        // Remove & cancel any existing sessions for the same key
        let stale_ids: Vec<u64> = mgr
            .sessions
            .iter()
            .filter_map(|(&id, s)| if s.key == key { Some(id) } else { None })
            .collect();
        for id in stale_ids {
            if let Some(s) = mgr.sessions.remove(&id) {
                s.cancelled.store(true, Ordering::SeqCst);
                s.kill_child();
            }
        }

        // LRU eviction when at capacity
        while mgr.sessions.len() >= MAX_CACHED_SESSIONS {
            let evict_idle = mgr
                .sessions
                .iter()
                .filter(|(_, s)| !s.scanning.load(Ordering::Acquire))
                .min_by_key(|(_, s)| s.last_used.load(Ordering::Relaxed))
                .map(|(&id, _)| id);

            let evict_id = evict_idle.or_else(|| {
                mgr.sessions
                    .iter()
                    .min_by_key(|(_, s)| s.last_used.load(Ordering::Relaxed))
                    .map(|(&id, _)| id)
            });

            match evict_id {
                Some(id) => {
                    if let Some(s) = mgr.sessions.remove(&id) {
                        s.cancelled.store(true, Ordering::SeqCst);
                        s.kill_child();
                    }
                }
                None => break,
            }
        }

        mgr.next_id += 1;
        let id = mgr.next_id;
        let cap = explicit_limit.unwrap_or(DEFAULT_MAX_COMMITS).max(1);
        let has_commits = !head_oid.is_empty();

        let session = Arc::new(GitLogSession {
            id,
            key,
            head_oid: head_oid.clone(),
            branch: branch.clone(),
            explicit_limit,
            commits: RwLock::new(Vec::new()),
            count: AtomicUsize::new(0),
            scanning: AtomicBool::new(has_commits),
            has_more: AtomicBool::new(false),
            cancelled: AtomicBool::new(false),
            revision: AtomicU64::new(0),
            max_commits: AtomicUsize::new(cap),
            error: Mutex::new(None),
            active_child: Mutex::new(None),
            last_used: AtomicU64::new(now_use),
        });

        mgr.sessions.insert(id, Arc::clone(&session));
        (session, has_commits)
    };

    if to_spawn {
        spawn_worker(Arc::clone(&session_opt));
    }

    Ok(GitLogOpenOut {
        session_id: session_opt.id,
        branch,
        head_oid,
        cached: false,
        scanning: to_spawn,
        total_items: 0,
        has_more: false,
        revision: 0,
    })
}

fn get_session(session_id: u64) -> Result<Option<Arc<GitLogSession>>, String> {
    let mut mgr = manager()
        .lock()
        .map_err(|_| "GitLogManager mutex poisoned".to_string())?;
    if let Some(s) = mgr.sessions.get(&session_id).cloned() {
        mgr.use_clock += 1;
        let now_use = mgr.use_clock;
        s.last_used.store(now_use, Ordering::Relaxed);
        return Ok(Some(s));
    }
    Ok(None)
}

pub fn session_status(session_id: u64) -> Result<GitLogStatusOut, String> {
    let s = {
        let mgr = manager()
            .lock()
            .map_err(|_| "GitLogManager mutex poisoned".to_string())?;
        mgr.sessions.get(&session_id).cloned()
    };

    let Some(session) = s else {
        return Ok(GitLogStatusOut {
            exists: false,
            scanning: false,
            total_items: 0,
            has_more: false,
            revision: 0,
            error: None,
        });
    };

    let err = session.error.lock().ok().and_then(|g| g.clone());
    Ok(GitLogStatusOut {
        exists: true,
        scanning: session.scanning.load(Ordering::Acquire),
        total_items: session.count.load(Ordering::Acquire),
        has_more: session.has_more.load(Ordering::Acquire),
        revision: session.revision.load(Ordering::Acquire),
        error: err,
    })
}

pub fn search_session(
    session_id: u64,
    query: &str,
    limit: usize,
    offset: usize,
) -> Result<GitLogSearchOut, String> {
    let Some(session) = get_session(session_id)? else {
        return Ok(GitLogSearchOut {
            exists: false,
            items: Vec::new(),
            total_matched: 0,
            total_items: 0,
            scanning: false,
            has_more: false,
            revision: 0,
            error: None,
        });
    };

    let commits_guard = session
        .commits
        .read()
        .map_err(|_| "Session commits lock poisoned".to_string())?;
    let scanning = session.scanning.load(Ordering::Acquire);
    let has_more = session.has_more.load(Ordering::Acquire);
    let revision = session.revision.load(Ordering::Acquire);
    let error = session.error.lock().ok().and_then(|g| g.clone());

    let (items, total_matched, total_items) =
        search_commits_slice(&commits_guard, query, limit, offset);

    Ok(GitLogSearchOut {
        exists: true,
        items,
        total_matched,
        total_items,
        scanning,
        has_more,
        revision,
        error,
    })
}

pub fn load_more(session_id: u64, add_count: usize) -> Result<GitLogLoadMoreOut, String> {
    let Some(session) = get_session(session_id)? else {
        return Ok(GitLogLoadMoreOut {
            started: false,
            queued: false,
            already_complete: true,
            total_items: 0,
            max_commits: 0,
        });
    };

    let add = add_count.max(1);
    let prev_max = session.max_commits.fetch_add(add, Ordering::SeqCst);
    let new_max = prev_max + add;

    if session
        .scanning
        .compare_exchange(false, true, Ordering::SeqCst, Ordering::SeqCst)
        .is_ok()
    {
        if !session.has_more.load(Ordering::SeqCst) || session.cancelled.load(Ordering::SeqCst) {
            session.scanning.store(false, Ordering::SeqCst);
            return Ok(GitLogLoadMoreOut {
                started: false,
                queued: false,
                already_complete: true,
                total_items: session.count.load(Ordering::Acquire),
                max_commits: new_max,
            });
        }
        session.revision.fetch_add(1, Ordering::Release);
        spawn_worker(Arc::clone(&session));
        return Ok(GitLogLoadMoreOut {
            started: true,
            queued: false,
            already_complete: false,
            total_items: session.count.load(Ordering::Acquire),
            max_commits: new_max,
        });
    }

    Ok(GitLogLoadMoreOut {
        started: false,
        queued: true,
        already_complete: false,
        total_items: session.count.load(Ordering::Acquire),
        max_commits: new_max,
    })
}

pub fn cancel_session(session_id: u64, only_if_scanning: bool) -> Result<bool, String> {
    let mut mgr = manager()
        .lock()
        .map_err(|_| "GitLogManager mutex poisoned".to_string())?;

    let Some(s) = mgr.sessions.get(&session_id) else {
        return Ok(false);
    };

    if only_if_scanning && !s.scanning.load(Ordering::Acquire) {
        return Ok(false);
    }

    if let Some(removed) = mgr.sessions.remove(&session_id) {
        removed.cancelled.store(true, Ordering::SeqCst);
        removed.kill_child();
        return Ok(true);
    }

    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn test_lock() -> &'static Mutex<()> {
        static TEST_MUTEX: OnceLock<Mutex<()>> = OnceLock::new();
        TEST_MUTEX.get_or_init(|| Mutex::new(()))
    }

    fn dotfiles_root() -> PathBuf {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .ancestors()
            .nth(5)
            .expect("dotfiles root")
            .to_path_buf()
    }

    fn wait_session_idle(session_id: u64, timeout_ms: u64) -> GitLogStatusOut {
        let start = Instant::now();
        loop {
            let st = session_status(session_id).expect("status");
            if !st.scanning {
                return st;
            }
            assert!(
                start.elapsed() < Duration::from_millis(timeout_ms),
                "timed out waiting for git_log session {session_id}"
            );
            std::thread::sleep(Duration::from_millis(10));
        }
    }

    #[test]
    fn git_log_streams_and_searches_dotfiles_repo() {
        let _guard = test_lock().lock().unwrap_or_else(|e| e.into_inner());
        let root = dotfiles_root();
        let root_str = root.to_string_lossy();
        let opened = open_session(&root_str, None, None, None, true).expect("open_session");
        assert!(!opened.cached);
        assert!(!opened.branch.is_empty());

        let st = wait_session_idle(opened.session_id, 10_000);
        assert!(st.exists);
        assert!(!st.scanning);
        assert!(!st.has_more);
        assert!(st.error.is_none());
        assert!(st.total_items > 1000);

        let res = search_session(opened.session_id, "first commit", 50, 0).expect("search");
        assert!(res.total_matched >= 1);
        assert!(res
            .items
            .iter()
            .any(|it| it.display.contains("first commit") && !it.match_indices.is_empty()));

        let _ = cancel_session(opened.session_id, false);
    }

    #[test]
    fn git_log_cache_hit_and_force_bypass() {
        let _guard = test_lock().lock().unwrap_or_else(|e| e.into_inner());
        let root = dotfiles_root();
        let root_str = root.to_string_lossy();

        let first = open_session(&root_str, None, None, None, true).expect("first open");
        let st = wait_session_idle(first.session_id, 10_000);
        assert!(st.total_items > 1000);

        let second = open_session(&root_str, None, None, None, false).expect("second open");
        assert!(second.cached);
        assert_eq!(second.session_id, first.session_id);
        assert_eq!(second.total_items, st.total_items);

        let forced = open_session(&root_str, None, None, None, true).expect("forced open");
        assert!(!forced.cached);
        assert_ne!(forced.session_id, first.session_id);
        let old_st = session_status(first.session_id).expect("old status");
        assert!(!old_st.exists);

        wait_session_idle(forced.session_id, 10_000);
        let _ = cancel_session(forced.session_id, false);
    }

    #[test]
    fn git_log_cap_load_more_and_cancel() {
        let _guard = test_lock().lock().unwrap_or_else(|e| e.into_inner());
        let root = dotfiles_root();
        let root_str = root.to_string_lossy();

        let opened = open_session(&root_str, None, None, Some(50), true).expect("capped open");
        let st1 = wait_session_idle(opened.session_id, 10_000);
        assert_eq!(st1.total_items, 50);
        assert!(st1.has_more);

        let lm = load_more(opened.session_id, 50).expect("load_more");
        assert!(lm.started || lm.queued);
        let st2 = wait_session_idle(opened.session_id, 10_000);
        assert_eq!(st2.total_items, 100);
        assert!(st2.has_more);

        let res = search_session(opened.session_id, "", 200, 0).expect("list 100");
        assert_eq!(res.items.len(), 100);
        let mut seen = HashSet::new();
        for (i, item) in res.items.iter().enumerate() {
            assert_eq!(item.order_idx, i + 1);
            assert!(seen.insert(item.hash.clone()), "duplicate hash at {i}");
        }

        // Completed session stays cached when only_if_scanning=true
        assert!(!cancel_session(opened.session_id, true).expect("cancel idle"));
        assert!(session_status(opened.session_id).expect("still exists").exists);

        // Forced cancel removes it
        assert!(cancel_session(opened.session_id, false).expect("cancel force"));
        assert!(!session_status(opened.session_id).expect("gone").exists);
    }

    #[test]
    fn git_log_100k_parallel_fuzzy_search() {
        let mut entries = Vec::with_capacity(100_000);
        for i in 0..100_000usize {
            let display = if i == 99_999 {
                format!("{:07x}  2018-01-01  Matsui54  initial bootstrap neovim target commit #{i}", i + 1)
            } else {
                format!("{:07x}  2025-05-01  Contributor{}  feat(mod{}): refactor subsystem part #{i}", i + 1, i % 100, i % 40)
            };
            entries.push(CommitEntry {
                hash: format!("{i:040x}").into_boxed_str(),
                display: display.into_boxed_str(),
                short_len: 7,
                date_start: 9,
                date_end: 19,
                author_start: 21,
                author_end: 33,
                refs_start: 0,
                refs_end: 0,
                has_parent: true,
            });
        }

        let t0 = Instant::now();
        let (items, total_matched, total_items) =
            search_commits_slice(&entries, "bootstrap target neovim", 200, 0);
        let elapsed_ms = t0.elapsed().as_secs_f64() * 1000.0;
        eprintln!("[bench] 100k commits parallel frizbee search: {elapsed_ms:.2}ms (matched={total_matched})");

        assert_eq!(total_items, 100_000);
        assert!(total_matched >= 1);
        assert_eq!(items[0].order_idx, 100_000);
        assert!(!items[0].match_indices.is_empty());
    }
}
