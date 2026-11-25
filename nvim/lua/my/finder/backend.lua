local M = {}

local uv = vim.uv or vim.loop

local function get_finder_dir()
  local source = debug.getinfo(1, 'S').source
  if source:sub(1, 1) == '@' then
    source = source:sub(2)
  end
  return vim.fn.fnamemodify(source, ':p:h')
end

local FINDER_DIR = get_finder_dir()
local RUST_DIR = FINDER_DIR .. '/rust'

local function shared_ext()
  local sys = uv.os_uname().sysname
  if sys == 'Darwin' then
    return 'dylib'
  elseif sys:match('Windows') then
    return 'dll'
  end
  return 'so'
end

local NATIVE_EXT = shared_ext()
local NATIVE_PATH = FINDER_DIR .. '/native.' .. NATIVE_EXT
local TARGET_PATH = RUST_DIR .. '/target/release/libmy_finder_native.' .. NATIVE_EXT

local native = nil
local load_attempted = false
local load_error = nil
local initialized = false
local TRACK_COOLDOWN_SEC = 30
local last_tracked_at = {}

---@return table|nil, string|nil
local function load_native()
  if native then
    return native, nil
  end
  if load_attempted then
    return nil, load_error
  end
  load_attempted = true

  local candidates = { NATIVE_PATH, TARGET_PATH }
  local last_err = 'native shared library not found'
  for _, path in ipairs(candidates) do
    if uv.fs_stat(path) then
      local fn, err = package.loadlib(path, 'luaopen_my_finder_native')
      if fn then
        local ok, mod = pcall(fn)
        if ok and type(mod) == 'table' then
          native = mod
          load_error = nil
          return native, nil
        else
          last_err = tostring(mod)
        end
      else
        last_err = tostring(err)
      end
    end
  end

  load_error = last_err
  return nil, load_error
end

---@return string|nil
local function resolve_rustup_toolchain()
  if vim.fn.executable('rustup') ~= 1 then
    return nil
  end
  local out = vim.fn.systemlist({ 'rustup', 'default' })
  if vim.v.shell_error == 0 and out[1] then
    return out[1]:match('^(%S+)')
  end
  return nil
end

---@param opts? { sync?: boolean, on_done?: fun(ok: boolean, msg: string) }
---@return boolean
function M.build(opts)
  opts = opts or {}
  local env = nil
  local toolchain = resolve_rustup_toolchain()
  if toolchain then
    env = { RUSTUP_TOOLCHAIN = toolchain }
  end

  local cmd = { 'cargo', 'build', '--release', '--locked' }

  local function finalize(res)
    if res.code ~= 0 then
      local msg = 'my.finder cargo build failed:\n' .. (res.stderr or '')
      if opts.on_done then
        opts.on_done(false, msg)
      else
        vim.notify(msg, vim.log.levels.ERROR)
      end
      return false
    end

    local ok_copy, copy_err = uv.fs_copyfile(TARGET_PATH, NATIVE_PATH)
    if not ok_copy then
      local msg = 'my.finder failed to copy native lib: ' .. tostring(copy_err)
      if opts.on_done then
        opts.on_done(false, msg)
      else
        vim.notify(msg, vim.log.levels.ERROR)
      end
      return false
    end

    native = nil
    load_attempted = false
    load_error = nil
    initialized = false

    local msg = 'my.finder native core built successfully'
    if opts.on_done then
      opts.on_done(true, msg)
    else
      vim.notify(msg, vim.log.levels.INFO)
    end
    return true
  end

  if opts.sync then
    local res = vim.system(cmd, { cwd = RUST_DIR, env = env }):wait()
    return finalize(res)
  end

  vim.notify('my.finder: building Rust core...', vim.log.levels.INFO)
  vim.system(cmd, { cwd = RUST_DIR, env = env }, function(res)
    vim.schedule(function()
      finalize(res)
    end)
  end)
  return true
end

---@return boolean
function M.is_available()
  local mod = load_native()
  return mod ~= nil
end

---@return string|nil
function M.last_error()
  return load_error
end

---@param opts? { state_dir?: string, base_path?: string }
---@return boolean
function M.init(opts)
  opts = opts or {}
  local mod, err = load_native()
  if not mod then
    if not opts.quiet then
      vim.notify('my.finder: native core unavailable (' .. tostring(err) .. '). Run :MyFinderBuild', vim.log.levels.WARN)
    end
    return false
  end

  if initialized and not opts.force then
    if opts.base_path and opts.base_path ~= '' then
      pcall(mod.ensure_dir, opts.base_path)
    end
    return true
  end

  local state_dir = opts.state_dir or vim.fs.joinpath(vim.fn.stdpath('state'), 'my_finder')
  local base_path = opts.base_path or vim.fn.getcwd()
  local ok, call_err = pcall(mod.init, {
    state_dir = state_dir,
    base_path = base_path,
  })
  if not ok then
    -- Home dir or root dir may intentionally decline scanning; still initialize LMDB without base_path
    local ok2 = pcall(mod.init, { state_dir = state_dir })
    initialized = ok2
    if not ok2 and not opts.quiet then
      vim.notify('my.finder init failed: ' .. tostring(call_err), vim.log.levels.WARN)
    end
    return ok2
  end

  initialized = true
  return true
end

---@param dir string
---@return string|nil, string|nil
function M.ensure_dir(dir)
  if not M.init({ quiet = true }) then
    return nil, load_error or 'native core not loaded'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error
  end
  local ok, res = pcall(mod.ensure_dir, dir)
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param dir string
---@return { scanning: boolean, total_files: integer }
function M.scan_status(dir)
  local mod = load_native()
  if not mod then
    return { scanning = false, total_files = 0 }
  end
  local ok, res = pcall(mod.scan_status, dir)
  if not ok or type(res) ~= 'table' then
    return { scanning = false, total_files = 0 }
  end
  return res
end

---@param dir string
---@param query string
---@param opts? { limit?: integer, current_file?: string }
---@return table|nil, string|nil
function M.search_files(dir, query, opts)
  if not M.init({ quiet = true }) then
    return nil, load_error or 'native core not loaded'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error
  end
  local ok, res = pcall(mod.search_files, dir, query or '', opts or {})
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param dir string
---@param query string
---@param opts? { limit?: integer, max_matches_per_file?: integer }
---@return table|nil, string|nil
function M.live_grep(dir, query, opts)
  if not M.init({ quiet = true }) then
    return nil, load_error or 'native core not loaded'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error
  end
  local ok, res = pcall(mod.live_grep, dir, query or '', opts or {})
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param path string
---@param opts? { force?: boolean }
function M.track_access(path, opts)
  if not path or path == '' then
    return
  end
  local mod = load_native()
  if not mod or not initialized then
    return
  end
  local norm = vim.fs.normalize(path)
  local now = os.time()
  if (not opts or not opts.force) and (now - (last_tracked_at[norm] or 0)) < TRACK_COOLDOWN_SEC then
    return
  end
  last_tracked_at[norm] = now
  pcall(mod.track_access, path)
end

---@param dir string
---@param query string
---@param path string
function M.track_query(dir, query, path)
  if not dir or dir == '' or not query or query == '' or not path or path == '' then
    return
  end
  local mod = load_native()
  if mod and initialized then
    pcall(mod.track_query, dir, query, path)
  end
end

---@param query string
---@param items string[]
---@param opts? { limit?: integer }
---@return { items: { idx: integer, score: integer, match_indices: integer[] }[], total_matched: integer, total_items: integer }
function M.fuzzy_match_list(query, items, opts)
  opts = opts or {}
  local limit = opts.limit or 200
  local mod = load_native()
  if mod then
    local ok, res = pcall(mod.fuzzy_match_list, query or '', items, { limit = limit })
    if ok and type(res) == 'table' then
      return res
    end
  end

  -- Fallback if native core is not yet compiled
  if not query or vim.trim(query) == '' then
    local out = {}
    local n = math.min(limit, #items)
    for i = 1, n do
      out[i] = { idx = i, score = 0, match_indices = {} }
    end
    return { items = out, total_matched = #items, total_items = #items }
  end

  local res = vim.fn.matchfuzzypos(items, query)
  local matched_texts = res[1] or {}
  local positions = res[2] or {}
  local scores = res[3] or {}

  local text_to_indices = {}
  for idx, s in ipairs(items) do
    text_to_indices[s] = text_to_indices[s] or {}
    table.insert(text_to_indices[s], idx)
  end
  local used_cursor = {}

  local out = {}
  local n = math.min(limit, #matched_texts)
  for i = 1, n do
    local t = matched_texts[i]
    local q = text_to_indices[t]
    local cursor = (used_cursor[t] or 0) + 1
    used_cursor[t] = cursor
    local orig_idx = q and q[cursor]
    if orig_idx then
      out[#out + 1] = {
        idx = orig_idx,
        score = scores[i] or 0,
        match_indices = positions[i] or {},
      }
    end
  end
  return { items = out, total_matched = #matched_texts, total_items = #items }
end

---@param git_root string
---@param query string
---@param items { section?: string, code?: string, rel_path?: string, match_text?: string }[]
---@param opts? { limit?: integer, current_file?: string }
---@return { items: { idx: integer, score: integer, match_indices: integer[] }[], total_matched: integer, total_items: integer }
function M.search_git_status(git_root, query, items, opts)
  opts = opts or {}
  items = items or {}
  local limit = opts.limit
  if limit == nil then
    limit = 500
  end

  M.init({ quiet = true })
  local mod = load_native()
  if mod and type(mod.search_git_status) == 'function' then
    local ok, res = pcall(mod.search_git_status, git_root or '', query or '', items, {
      limit = limit,
      current_file = opts.current_file,
    })
    if ok and type(res) == 'table' then
      return res
    end
  end

  -- Fallback when native core is not yet compiled or lacks search_git_status:
  -- preserve staged before unstaged grouping via per-group fuzzy matching.
  local staged_indices = {}
  local staged_texts = {}
  local unstaged_indices = {}
  local unstaged_texts = {}

  for i, it in ipairs(items) do
    local text = it.match_text or it.rel_path or ''
    if it.section == 'staged' then
      staged_indices[#staged_indices + 1] = i
      staged_texts[#staged_texts + 1] = text
    else
      unstaged_indices[#unstaged_indices + 1] = i
      unstaged_texts[#unstaged_texts + 1] = text
    end
  end

  local group_limit = (limit > 0) and limit or math.max(1, #items)
  local staged_res = (#staged_texts > 0)
    and M.fuzzy_match_list(query or '', staged_texts, { limit = group_limit })
    or { items = {}, total_matched = 0 }
  local unstaged_res = (#unstaged_texts > 0)
    and M.fuzzy_match_list(query or '', unstaged_texts, { limit = group_limit })
    or { items = {}, total_matched = 0 }

  local out = {}
  for _, m in ipairs(staged_res.items or {}) do
    if limit > 0 and #out >= limit then
      break
    end
    out[#out + 1] = {
      idx = staged_indices[m.idx],
      score = m.score or 0,
      match_indices = m.match_indices or {},
    }
  end
  for _, m in ipairs(unstaged_res.items or {}) do
    if limit > 0 and #out >= limit then
      break
    end
    out[#out + 1] = {
      idx = unstaged_indices[m.idx],
      score = m.score or 0,
      match_indices = m.match_indices or {},
    }
  end

  local total_matched = (staged_res.total_matched or 0) + (unstaged_res.total_matched or 0)
  return {
    items = out,
    total_matched = total_matched,
    total_items = #items,
  }
end

---@param opts table
---@return table|nil, string|nil
function M.git_log_open(opts)
  if not M.init({ quiet = true }) then
    return nil, load_error or 'native core not loaded'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error
  end
  local ok, res = pcall(mod.git_log_open, opts)
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param session_id integer
---@return table|nil, string|nil
function M.git_log_status(session_id)
  if not session_id then
    return nil, 'missing session_id'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error or 'native core not loaded'
  end
  local ok, res = pcall(mod.git_log_status, session_id)
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param session_id integer
---@param query string
---@param opts? { limit?: integer, offset?: integer }
---@return table|nil, string|nil
function M.git_log_search(session_id, query, opts)
  if not session_id then
    return nil, 'missing session_id'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error or 'native core not loaded'
  end
  local ok, res = pcall(mod.git_log_search, session_id, query or '', opts or {})
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param session_id integer
---@param add_count? integer
---@return table|nil, string|nil
function M.git_log_load_more(session_id, add_count)
  if not session_id then
    return nil, 'missing session_id'
  end
  local mod = load_native()
  if not mod then
    return nil, load_error or 'native core not loaded'
  end
  local ok, res = pcall(mod.git_log_load_more, session_id, add_count)
  if not ok then
    return nil, tostring(res)
  end
  return res, nil
end

---@param session_id integer|nil
---@param opts? { only_if_scanning?: boolean }
---@return boolean
function M.git_log_cancel(session_id, opts)
  if not session_id then
    return false
  end
  local mod = load_native()
  if not mod then
    return false
  end
  local ok, res = pcall(mod.git_log_cancel, session_id, opts)
  return ok and res == true
end

return M
