use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

use fff_search::file_picker::FFFMode;
use fff_search::path_utils::calculate_distance_penalty;
use fff_search::query_tracker::QueryMatchEntry;
use fff_search::SharedFilePicker;
use frizbee::{Config as FrizbeeConfig, Matcher as FrizbeeMatcher, Pattern as FrizbeePattern};

const MODIFICATION_THRESHOLDS: [(i64, u64); 5] = [
    (16, 60 * 2),          // 2 minutes
    (8, 60 * 15),          // 15 minutes
    (4, 60 * 60),          // 1 hour
    (2, 60 * 60 * 24),     // 1 day
    (1, 60 * 60 * 24 * 7), // 1 week
];

pub struct GitStatusEntryIn {
    pub section: u8,
    pub code: String,
    pub rel_path: String,
    pub match_text: String,
}

pub struct GitStatusMatchOut {
    pub idx: usize,
    pub score: i32,
    pub match_indices: Vec<u32>,
}

pub struct GitStatusSearchOut {
    pub items: Vec<GitStatusMatchOut>,
    pub total_matched: usize,
    pub total_items: usize,
}

#[derive(Clone, Debug)]
pub(crate) struct EntrySignals {
    pub access_frecency: i32,
    pub modification_frecency: i32,
    pub git_recency: i32,
    pub modified: u64,
    pub is_modified: bool,
    pub abs_path: PathBuf,
}

pub fn is_modified_code(code: &str) -> bool {
    let trimmed = code.trim();
    !trimmed.is_empty() && trimmed != "D"
}

pub fn compute_modification_score(modified_time: u64, is_modified: bool, now: u64) -> i32 {
    if !is_modified || modified_time == 0 {
        return 0;
    }

    let duration_since = now.saturating_sub(modified_time);
    for (i, &(current_points, current_threshold)) in MODIFICATION_THRESHOLDS.iter().enumerate() {
        if duration_since <= current_threshold {
            if i == 0 || duration_since == current_threshold {
                return current_points as i32;
            }
            let (prev_points, prev_threshold) = MODIFICATION_THRESHOLDS[i - 1];
            let time_range = current_threshold - prev_threshold;
            let time_offset = duration_since - prev_threshold;
            let points_diff = prev_points - current_points;
            let interpolated =
                prev_points - (points_diff * time_offset as i64) / time_range as i64;
            return interpolated as i32;
        }
    }

    0
}

fn is_special_entry_point_file(filename: &str) -> bool {
    matches!(
        filename,
        "mod.rs"
            | "lib.rs"
            | "main.rs"
            | "index.js"
            | "index.jsx"
            | "index.ts"
            | "index.tsx"
            | "index.mjs"
            | "index.cjs"
            | "index.vue"
            | "__init__.py"
            | "__main__.py"
            | "main.go"
            | "main.c"
            | "index.php"
            | "main.rb"
            | "index.rb"
    )
}

fn empty_query_score(sig: &EntrySignals) -> i32 {
    let total_frecency = sig
        .access_frecency
        .saturating_add(sig.modification_frecency.saturating_mul(4));
    let git_status_boost = if sig.is_modified {
        total_frecency.saturating_mul(15) / 100
    } else {
        0
    };
    total_frecency
        .saturating_add(git_status_boost)
        .saturating_add(sig.git_recency)
}

fn path_ends_with_rel(full_path: &Path, rel_path: &str) -> bool {
    if rel_path.is_empty() {
        return false;
    }
    let full_str = full_path.to_string_lossy();
    if !full_str.ends_with(rel_path) {
        return false;
    }
    if full_str.len() == rel_path.len() {
        return true;
    }
    let boundary_idx = full_str.len() - rel_path.len() - 1;
    full_str
        .as_bytes()
        .get(boundary_idx)
        .is_some_and(|&b| b == b'/' || b == b'\\')
}

fn score_fuzzy_match(
    base_score: i32,
    entry: &GitStatusEntryIn,
    sig: &EntrySignals,
    main_needle: &str,
    query_contains_path_separator: bool,
    filename_matcher: &mut Option<FrizbeeMatcher>,
    current_file: Option<&str>,
    last_same_query_match: Option<&QueryMatchEntry>,
) -> i32 {
    let total_frecency = sig.access_frecency.saturating_add(sig.modification_frecency);
    let frecency_boost = base_score.saturating_mul(total_frecency) / 100;
    let git_status_boost = if sig.is_modified {
        base_score.saturating_mul(15) / 100
    } else {
        0
    };
    let git_recency_boost = sig.git_recency;

    let candidate_dir = match entry.rel_path.rfind('/') {
        Some(pos) => &entry.rel_path[..=pos],
        None => "",
    };
    let distance_penalty = calculate_distance_penalty(current_file, candidate_dir);

    let filename = match entry.rel_path.rfind('/') {
        Some(pos) => &entry.rel_path[pos + 1..],
        None => entry.rel_path.as_str(),
    };

    let filename_bonus = if !query_contains_path_separator {
        if main_needle.eq_ignore_ascii_case(filename) {
            base_score / 5 * 2
        } else if let Some(fm) = filename_matcher
            .as_mut()
            .and_then(|m| m.match_list(&[filename]).into_iter().next())
        {
            let max_bonus = (base_score / 6).min(30);
            let max_possible = (main_needle.len() as i32 * 16).max(1);
            let quality = (fm.score as i32).min(max_possible);
            max_bonus * quality / max_possible
        } else if (5..=11).contains(&filename.len()) && is_special_entry_point_file(filename) {
            base_score * 5 / 100
        } else {
            0
        }
    } else {
        0
    };

    let path_alignment_bonus = if query_contains_path_separator {
        let needle_bytes = main_needle.as_bytes();
        let path_bytes = entry.rel_path.as_bytes();
        let common_suffix = needle_bytes
            .iter()
            .rev()
            .zip(path_bytes.iter().rev())
            .take_while(|(n, p)| n.eq_ignore_ascii_case(p))
            .count();
        let needle_len = needle_bytes.len();
        if common_suffix > 10 && needle_len > 0 {
            let coverage = common_suffix * 100 / needle_len;
            if coverage >= 30 {
                base_score.saturating_mul(coverage as i32) / 100
            } else {
                0
            }
        } else {
            0
        }
    } else {
        0
    };

    let combo_match_boost = match last_same_query_match {
        Some(cm) if cm.file_path == sig.abs_path || path_ends_with_rel(&cm.file_path, &entry.rel_path) => {
            if cm.open_count >= 3 {
                cm.open_count as i32 * 100
            } else {
                cm.open_count as i32 * 5
            }
        }
        _ => 0,
    };

    base_score
        .saturating_add(frecency_boost)
        .saturating_add(git_status_boost)
        .saturating_add(git_recency_boost)
        .saturating_add(distance_penalty)
        .saturating_add(filename_bonus)
        .saturating_add(combo_match_boost)
        .saturating_add(path_alignment_bonus)
}

pub(crate) fn search_with_signals(
    entries: &[GitStatusEntryIn],
    signals: &[EntrySignals],
    query: &str,
    limit: usize,
    current_file: Option<&str>,
    last_same_query_match: Option<&QueryMatchEntry>,
) -> GitStatusSearchOut {
    assert_eq!(entries.len(), signals.len());
    let total_items = entries.len();
    if total_items == 0 {
        return GitStatusSearchOut {
            items: Vec::new(),
            total_matched: 0,
            total_items: 0,
        };
    }

    let trimmed = query.trim();
    if trimmed.is_empty() {
        let mut scored: Vec<(usize, i32)> = (0..total_items)
            .map(|i| (i, empty_query_score(&signals[i])))
            .collect();
        scored.sort_unstable_by(|&(idx_a, score_a), &(idx_b, score_b)| {
            entries[idx_a]
                .section
                .cmp(&entries[idx_b].section)
                .then_with(|| score_b.cmp(&score_a))
                .then_with(|| signals[idx_b].modified.cmp(&signals[idx_a].modified))
                .then_with(|| idx_a.cmp(&idx_b))
        });

        let total_matched = scored.len();
        if limit > 0 {
            scored.truncate(limit);
        }

        let items = scored
            .into_iter()
            .map(|(i, score)| GitStatusMatchOut {
                idx: i + 1,
                score,
                match_indices: Vec::new(),
            })
            .collect();

        return GitStatusSearchOut {
            items,
            total_matched,
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

    if patterns.is_empty() {
        return search_with_signals(entries, signals, "", limit, current_file, last_same_query_match);
    }

    let cfg = FrizbeeConfig::default();
    let mut matcher = FrizbeeMatcher::from_patterns(&patterns, &cfg);
    let haystacks: Vec<&str> = entries.iter().map(|e| e.match_text.as_str()).collect();
    let matches = matcher.match_list(&haystacks);
    let total_matched = matches.len();

    let positive_patterns: Vec<&FrizbeePattern> = patterns
        .iter()
        .filter(|p| !p.negated && !p.needle.is_empty())
        .collect();

    let mut scored: Vec<(usize, i32)> = if positive_patterns.is_empty() {
        matches
            .into_iter()
            .map(|m| {
                let i = m.index as usize;
                (i, empty_query_score(&signals[i]))
            })
            .collect()
    } else {
        let main_pattern = positive_patterns[0];
        let main_needle = main_pattern.needle.as_str();
        let query_contains_path_separator = positive_patterns
            .iter()
            .any(|p| p.needle.contains('/') || p.needle.contains(std::path::MAIN_SEPARATOR));
        let mut filename_matcher = (!query_contains_path_separator)
            .then(|| FrizbeeMatcher::from_patterns(&[main_pattern.clone()], &cfg));

        matches
            .into_iter()
            .map(|m| {
                let i = m.index as usize;
                let total = score_fuzzy_match(
                    m.score as i32,
                    &entries[i],
                    &signals[i],
                    main_needle,
                    query_contains_path_separator,
                    &mut filename_matcher,
                    current_file,
                    last_same_query_match,
                );
                (i, total)
            })
            .collect()
    };

    scored.sort_unstable_by(|&(idx_a, score_a), &(idx_b, score_b)| {
        entries[idx_a]
            .section
            .cmp(&entries[idx_b].section)
            .then_with(|| score_b.cmp(&score_a))
            .then_with(|| signals[idx_b].modified.cmp(&signals[idx_a].modified))
            .then_with(|| idx_a.cmp(&idx_b))
    });

    if limit > 0 {
        scored.truncate(limit);
    }

    let mut items = Vec::with_capacity(scored.len());
    for (i, score) in scored {
        let mut indices = Vec::new();
        let mut matched = matcher.match_list_indices(&[entries[i].match_text.as_str()]);
        if let Some(first) = matched.pop() {
            indices = first.indices;
            indices.sort_unstable();
            indices.dedup();
        }
        items.push(GitStatusMatchOut {
            idx: i + 1,
            score,
            match_indices: indices,
        });
    }

    GitStatusSearchOut {
        items,
        total_matched,
        total_items,
    }
}

pub fn search_git_status_impl(
    git_root: &str,
    query: &str,
    entries: &[GitStatusEntryIn],
    limit: usize,
    current_file: Option<&str>,
) -> Result<GitStatusSearchOut, String> {
    if entries.is_empty() {
        return Ok(GitStatusSearchOut {
            items: Vec::new(),
            total_matched: 0,
            total_items: 0,
        });
    }

    let canon_root = crate::normalize_path(git_root);
    let (shared_frecency, shared_query_tracker, candidate_pickers) = {
        let state = crate::global_state()
            .lock()
            .map_err(|_| "GlobalState mutex poisoned".to_string())?;
        let mut pickers: Vec<SharedFilePicker> = Vec::new();
        if let Some(exact) = state.pickers.get(&canon_root) {
            pickers.push(exact.clone());
        }
        for (dir, sp) in &state.pickers {
            if dir != &canon_root && (dir.starts_with(&canon_root) || canon_root.starts_with(dir)) {
                pickers.push(sp.clone());
            }
        }
        (
            state.frecency.clone(),
            state.query_tracker.clone(),
            pickers,
        )
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_or(0, |d| d.as_secs());

    let frecency_guard = shared_frecency
        .read()
        .map_err(|e| format!("Frecency lock error: {e}"))?;
    let tracker = frecency_guard.as_ref();

    let picker_guards: Vec<_> = candidate_pickers
        .iter()
        .filter_map(|sp| sp.read().ok())
        .collect();

    let mut signals = Vec::with_capacity(entries.len());
    for entry in entries {
        let raw_abs = canon_root.join(&entry.rel_path);
        let abs_path = std::fs::canonicalize(&raw_abs).unwrap_or_else(|_| raw_abs.clone());
        let modified = std::fs::metadata(&abs_path)
            .ok()
            .and_then(|m| m.modified().ok())
            .and_then(|t| t.duration_since(UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_secs());
        let is_modified = is_modified_code(&entry.code);
        let access_frecency = tracker
            .map(|t| t.get_access_score(&abs_path, FFFMode::Neovim) as i32)
            .unwrap_or(0);
        let modification_frecency = compute_modification_score(modified, is_modified, now);
        let git_recency = picker_guards
            .iter()
            .filter_map(|g| g.as_ref())
            .find_map(|picker| {
                picker
                    .get_file_by_path(&abs_path)
                    .or_else(|| picker.get_file_by_path(&raw_abs))
                    .map(|f| f.git_recency_score as i32)
            })
            .unwrap_or(0);

        signals.push(EntrySignals {
            access_frecency,
            modification_frecency,
            git_recency,
            modified,
            is_modified,
            abs_path,
        });
    }

    let trimmed = query.trim();
    let last_same_query_match = if trimmed.is_empty() {
        None
    } else {
        let qt_guard = shared_query_tracker
            .read()
            .map_err(|e| format!("QueryTracker lock error: {e}"))?;
        qt_guard
            .as_ref()
            .and_then(|qt| qt.get_last_query_entry(query, &canon_root, 3).ok().flatten())
    };

    Ok(search_with_signals(
        entries,
        &signals,
        query,
        limit,
        current_file,
        last_same_query_match.as_ref(),
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_entry(section: u8, code: &str, rel_path: &str) -> GitStatusEntryIn {
        GitStatusEntryIn {
            section,
            code: code.to_string(),
            rel_path: rel_path.to_string(),
            match_text: rel_path.to_string(),
        }
    }

    fn make_signal(
        rel_path: &str,
        access: i32,
        mod_frecency: i32,
        git_recency: i32,
        modified: u64,
        is_modified: bool,
    ) -> EntrySignals {
        EntrySignals {
            access_frecency: access,
            modification_frecency: mod_frecency,
            git_recency,
            modified,
            is_modified,
            abs_path: PathBuf::from("/repo").join(rel_path),
        }
    }

    #[test]
    fn modification_score_matches_fff_thresholds_and_interpolation() {
        let now = 1_700_000_000;
        assert_eq!(compute_modification_score(now - 60, true, now), 16);
        assert_eq!(compute_modification_score(now - 2 * 60, true, now), 16);
        assert_eq!(compute_modification_score(now - 5 * 60, true, now), 15);
        assert_eq!(compute_modification_score(now - 15 * 60, true, now), 8);
        assert_eq!(compute_modification_score(now - 12 * 3600, true, now), 4);
        assert_eq!(compute_modification_score(now - 18 * 3600, true, now), 3);
        assert_eq!(
            compute_modification_score(now - 7 * 86400 - 1, true, now),
            0
        );
        assert_eq!(compute_modification_score(now - 60, false, now), 0);
        assert_eq!(compute_modification_score(0, true, now), 0);
        assert!(!is_modified_code("D"));
        assert!(is_modified_code("M"));
        assert!(is_modified_code("??"));
        assert!(is_modified_code("A"));
    }

    #[test]
    fn empty_query_keeps_staged_before_unstaged_and_ranks_by_frecency_without_current_file_penalty(
    ) {
        let entries = vec![
            make_entry(0, "M", "staged_old.rs"),
            make_entry(0, "M", "staged_hot_current.rs"),
            make_entry(1, "M", "unstaged_older.rs"),
            make_entry(1, "??", "unstaged_newest.rs"),
            make_entry(1, "M", "unstaged_tie_older.rs"),
            make_entry(1, "M", "unstaged_tie_newer.rs"),
        ];
        let signals = vec![
            make_signal("staged_old.rs", 1, 0, 0, 100, true),
            // Even as current_file, it must NOT be penalized.
            make_signal("staged_hot_current.rs", 2, 16, 3, 200, true),
            // Huge score in unstaged, must still come after all staged items.
            make_signal("unstaged_older.rs", 5, 4, 0, 300, true),
            make_signal("unstaged_newest.rs", 0, 16, 10, 400, true),
            make_signal("unstaged_tie_older.rs", 2, 0, 0, 100, true),
            make_signal("unstaged_tie_newer.rs", 2, 0, 0, 500, true),
        ];

        let res = search_with_signals(
            &entries,
            &signals,
            "",
            0,
            Some("staged_hot_current.rs"),
            None,
        );
        let ordered_paths: Vec<&str> = res
            .items
            .iter()
            .map(|m| entries[m.idx - 1].rel_path.as_str())
            .collect();

        assert_eq!(
            ordered_paths,
            vec![
                "staged_hot_current.rs",
                "staged_old.rs",
                "unstaged_newest.rs",
                "unstaged_older.rs",
                "unstaged_tie_newer.rs",
                "unstaged_tie_older.rs",
            ]
        );
        // staged_hot_current: total_frecency = 2 + 16*4 = 66, boost = 66*15/100 = 9, git_recency = 3 -> 78
        assert_eq!(res.items[0].score, 78);
    }

    #[test]
    fn fuzzy_query_keeps_section_grouping_boosts_frecency_and_skips_current_file_penalty() {
        let entries = vec![
            make_entry(0, "M", "deep/staged_picker_helper.lua"),
            make_entry(1, "M", "src/a/picker.lua"),
            make_entry(1, "M", "src/b/picker.lua"),
            make_entry(1, "M", "far/other/picker_combo.lua"),
        ];
        let signals = vec![
            // Lower fuzzy score in staged, still ranks before unstaged.
            make_signal("deep/staged_picker_helper.lua", 0, 0, 0, 100, true),
            // Same dir as current_file ("src/a/cur.lua"), high modification frecency,
            // and even when it IS current_file it gets no penalty.
            make_signal("src/a/picker.lua", 4, 16, 2, 200, true),
            // Cold file in sibling dir.
            make_signal("src/b/picker.lua", 0, 0, 0, 200, true),
            // Combo boost target.
            make_signal("far/other/picker_combo.lua", 0, 0, 0, 200, true),
        ];

        let res = search_with_signals(&entries, &signals, "picker", 10, Some("src/a/picker.lua"), None);
        let ordered: Vec<&str> = res
            .items
            .iter()
            .map(|m| entries[m.idx - 1].rel_path.as_str())
            .collect();
        assert_eq!(ordered[0], "deep/staged_picker_helper.lua");
        assert_eq!(ordered[1], "src/a/picker.lua");
        assert_eq!(ordered[2], "src/b/picker.lua");
        assert!(res.items.iter().all(|m| !m.match_indices.is_empty()));

        // Verify combo boost lifts picker_combo.lua within unstaged.
        let combo = QueryMatchEntry {
            file_path: PathBuf::from("/repo/far/other/picker_combo.lua"),
            open_count: 3,
            last_opened: 1000,
        };
        let res_combo = search_with_signals(
            &entries,
            &signals,
            "picker",
            10,
            Some("src/a/picker.lua"),
            Some(&combo),
        );
        let ordered_combo: Vec<&str> = res_combo
            .items
            .iter()
            .map(|m| entries[m.idx - 1].rel_path.as_str())
            .collect();
        assert_eq!(ordered_combo[0], "deep/staged_picker_helper.lua");
        assert_eq!(ordered_combo[1], "far/other/picker_combo.lua");

        // Negation-only query falls back to empty-query frecency scoring for survivors.
        let res_neg = search_with_signals(&entries, &signals, "!combo", 10, None, None);
        let ordered_neg: Vec<&str> = res_neg
            .items
            .iter()
            .map(|m| entries[m.idx - 1].rel_path.as_str())
            .collect();
        assert_eq!(
            ordered_neg,
            vec![
                "deep/staged_picker_helper.lua",
                "src/a/picker.lua",
                "src/b/picker.lua",
            ]
        );
    }

    #[test]
    fn deleted_and_renamed_entries_handle_metadata_and_utf8_match_indices() {
        let entries = vec![
            GitStatusEntryIn {
                section: 1,
                code: "D".to_string(),
                rel_path: "removed.lua".to_string(),
                match_text: "removed.lua".to_string(),
            },
            GitStatusEntryIn {
                section: 1,
                code: "R".to_string(),
                rel_path: "new/picker.lua".to_string(),
                match_text: "old/日本語.lua -> new/picker.lua".to_string(),
            },
        ];
        let signals = vec![
            // Deleted entry: is_modified=false, modified=0, still preserves access_frecency
            make_signal("removed.lua", 5, compute_modification_score(0, is_modified_code("D"), 1000), 0, 0, false),
            make_signal("new/picker.lua", 1, 16, 0, 999, true),
        ];

        let empty_res = search_with_signals(&entries, &signals, "", 10, None, None);
        assert_eq!(empty_res.items[0].idx, 2);
        assert_eq!(empty_res.items[1].idx, 1);
        assert_eq!(empty_res.items[1].score, 5);

        let fuzzy_res = search_with_signals(&entries, &signals, "piker", 10, None, None);
        assert_eq!(fuzzy_res.total_matched, 1);
        assert_eq!(fuzzy_res.items[0].idx, 2);
        let hay = &entries[1].match_text;
        for &b in &fuzzy_res.items[0].match_indices {
            assert!((b as usize) < hay.len());
        }
    }
}
