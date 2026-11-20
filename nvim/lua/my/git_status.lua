local M = {}

local ns = vim.api.nvim_create_namespace('my_git_status')

local state = {
  buf = nil,
  root = nil,
  branch = nil,
  entries = {},      -- list of { section, code, path, orig_path, key }
  line_entries = {}, -- line_nr (1-based) -> entry
  marked = {},       -- key -> true
  loading = false,
  refresh_gen = 0,
  diff_tab_idx = nil,
  diff_gen = 0,
}

--- Run a git command synchronously and return result
---@param root string|nil
---@param args string[]
---@return vim.SystemCompleted
local function git_sync(root, args)
  local cmd = { 'git' }
  if root then
    vim.list_extend(cmd, { '-C', root })
  end
  vim.list_extend(cmd, args)
  return vim.system(cmd, { text = false }):wait()
end

--- Run a git command asynchronously
---@param root string
---@param args string[]
---@param on_done fun(res: vim.SystemCompleted)
local function git_async(root, args, on_done)
  local cmd = { 'git', '-C', root }
  vim.list_extend(cmd, args)
  vim.system(cmd, { text = false }, function(res)
    vim.schedule(function()
      on_done(res)
    end)
  end)
end

---@param path string
---@return string|nil
local function get_repo_root(path)
  local dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
  local res = git_sync(dir, { 'rev-parse', '--show-toplevel' })
  if res.code ~= 0 or not res.stdout then
    return nil
  end
  return vim.trim(res.stdout)
end

---@param root string
---@return string
local function get_branch(root)
  local res = git_sync(root, { 'rev-parse', '--abbrev-ref', 'HEAD' })
  if res.code ~= 0 or not res.stdout then
    return '(unknown)'
  end
  return vim.trim(res.stdout)
end

---@param raw string
---@return table[]
local function parse_status(raw)
  local entries = {}
  local items = vim.split(raw, '\0', { plain = true, trimempty = true })
  local i = 1

  while i <= #items do
    local item = items[i]
    if #item >= 4 then
      local x = item:sub(1, 1)
      local y = item:sub(2, 2)
      local path = item:sub(4)
      local orig_path = nil

      if x == 'R' or x == 'C' or y == 'R' or y == 'C' then
        i = i + 1
        orig_path = items[i]
      end

      if x == '?' and y == '?' then
        table.insert(entries, {
          section = 'unstaged',
          code = '??',
          path = path,
          orig_path = nil,
          key = 'unstaged:' .. path,
        })
      else
        if x ~= ' ' then
          table.insert(entries, {
            section = 'staged',
            code = x,
            path = path,
            orig_path = orig_path,
            key = 'staged:' .. path,
          })
        end
        if y ~= ' ' then
          table.insert(entries, {
            section = 'unstaged',
            code = y,
            path = path,
            orig_path = orig_path,
            key = 'unstaged:' .. path,
          })
        end
      end
    end
    i = i + 1
  end

  return entries
end

---@param code string
---@return string
local function hl_for_code(code)
  local c = code:sub(1, 1)
  if c == 'A' then
    return 'Added'
  elseif c == 'D' then
    return 'Removed'
  elseif c == 'M' or c == 'R' or c == 'C' then
    return 'Changed'
  elseif c == '?' then
    return 'Comment'
  elseif c == 'U' then
    return 'DiagnosticError'
  end
  return 'Normal'
end

local function render()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  -- Save current cursor entry key to restore position after render
  local win = vim.fn.bufwinid(buf)
  local prev_key = nil
  local prev_line = 1
  if win ~= -1 then
    prev_line = vim.api.nvim_win_get_cursor(win)[1]
    local prev_entry = state.line_entries[prev_line]
    if prev_entry then
      prev_key = prev_entry.key
    end
  end

  local staged = {}
  local unstaged = {}
  local valid_keys = {}
  for _, e in ipairs(state.entries) do
    valid_keys[e.key] = true
    if e.section == 'staged' then
      table.insert(staged, e)
    else
      table.insert(unstaged, e)
    end
  end

  -- Prune stale marks
  for k in pairs(state.marked) do
    if not valid_keys[k] then
      state.marked[k] = nil
    end
  end

  local lines = {}
  local highlights = {}
  state.line_entries = {}

  local function add_line(text, hl_group, col_start, col_end)
    table.insert(lines, text)
    local lnum = #lines - 1
    if hl_group then
      table.insert(highlights, { lnum, col_start or 0, col_end or -1, hl_group })
    end
    return #lines
  end

  local header = string.format('Repo: %s  [%s]', state.root or '', state.branch or '...')
  if state.loading then
    local lnum_1 = add_line(header .. '  (Loading...)')
    local lnum_0 = lnum_1 - 1
    table.insert(highlights, { lnum_0, 0, #header, 'Title' })
    table.insert(highlights, { lnum_0, #header + 2, -1, 'Comment' })
  else
    add_line(header, 'Title')
  end

  local function render_section(title, list)
    add_line(string.format('%s (%d)', title, #list), 'Title')
    if #list == 0 then
      -- add_line('  (empty)', 'Comment')
      return
    end
    for _, e in ipairs(list) do
      local mark = state.marked[e.key] and '*' or ' '
      local code_str = string.format('%-2s', e.code)
      local display_path = e.orig_path and (e.orig_path .. ' -> ' .. e.path) or e.path
      local text = string.format('%s %s %s', mark, code_str, display_path)
      local lnum_1 = add_line(text)
      state.line_entries[lnum_1] = e

      local lnum_0 = lnum_1 - 1
      if state.marked[e.key] then
        table.insert(highlights, { lnum_0, 0, 1, 'DiagnosticWarn' })
      end
      table.insert(highlights, { lnum_0, 2, 4, hl_for_code(e.code) })
    end
  end

  render_section('Staged', staged)
  add_line('')
  render_section('Unstaged / Untracked', unstaged)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, h in ipairs(highlights) do
    vim.api.nvim_buf_set_extmark(buf, ns, h[1], h[2], {
      end_col = h[3] == -1 and #lines[h[1] + 1] or h[3],
      hl_group = h[4],
    })
  end

  -- Restore cursor
  if win ~= -1 and vim.api.nvim_win_is_valid(win) then
    local target_line = nil
    if prev_key then
      for lnum, e in pairs(state.line_entries) do
        if e.key == prev_key then
          target_line = lnum
          break
        end
      end
    end
    target_line = target_line or math.min(prev_line, #lines)
    pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
  end
end

function M.refresh()
  if not state.root then
    return
  end
  state.refresh_gen = state.refresh_gen + 1
  local gen = state.refresh_gen
  state.loading = true
  render()

  git_async(state.root, { 'rev-parse', '--abbrev-ref', 'HEAD' }, function(res)
    if gen ~= state.refresh_gen then
      return
    end
    if res.code == 0 and res.stdout then
      state.branch = vim.trim(res.stdout)
    else
      state.branch = '(unknown)'
    end
    render()
  end)

  git_async(state.root, { 'status', '--porcelain=v1', '-z', '-uall' }, function(res)
    if gen ~= state.refresh_gen then
      return
    end
    state.loading = false
    if res.code ~= 0 then
      render()
      vim.notify('git status failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    state.entries = parse_status(res.stdout or '')
    render()
  end)
end

---@return integer, integer
local function get_visual_range()
  local l1 = vim.fn.line('v')
  local l2 = vim.fn.line('.')
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'nx', false)
  if l1 > l2 then
    return l2, l1
  end
  return l1, l2
end

---@param l1 integer
---@param l2 integer
---@return table[]
local function entries_in_range(l1, l2)
  local list = {}
  for l = l1, l2 do
    local e = state.line_entries[l]
    if e then
      table.insert(list, e)
    end
  end
  return list
end

---@param is_visual boolean
---@return table[], boolean
local function resolve_targets(is_visual)
  if is_visual then
    local l1, l2 = get_visual_range()
    return entries_in_range(l1, l2), false
  end

  if next(state.marked) ~= nil then
    local list = {}
    for _, e in ipairs(state.entries) do
      if state.marked[e.key] then
        table.insert(list, e)
      end
    end
    return list, true
  end

  local l = vim.api.nvim_win_get_cursor(0)[1]
  local e = state.line_entries[l]
  if e then
    return { e }, false
  end
  return {}, false
end

---@param list table[]
---@return string[]
local function collect_paths(list)
  local seen = {}
  local paths = {}
  for _, e in ipairs(list) do
    if e.orig_path and not seen[e.orig_path] then
      seen[e.orig_path] = true
      table.insert(paths, e.orig_path)
    end
    if not seen[e.path] then
      seen[e.path] = true
      table.insert(paths, e.path)
    end
  end
  return paths
end

---@param is_visual boolean
local function toggle_mark(is_visual)
  if is_visual then
    local l1, l2 = get_visual_range()
    for _, e in ipairs(entries_in_range(l1, l2)) do
      if state.marked[e.key] then
        state.marked[e.key] = nil
      else
        state.marked[e.key] = true
      end
    end
    render()
    return
  end

  local l = vim.api.nvim_win_get_cursor(0)[1]
  local e = state.line_entries[l]
  if e then
    if state.marked[e.key] then
      state.marked[e.key] = nil
    else
      state.marked[e.key] = true
    end
    render()
  end
  local last_line = vim.api.nvim_buf_line_count(state.buf)
  if l < last_line then
    vim.api.nvim_win_set_cursor(0, { l + 1, 0 })
  end
end

---@param is_visual boolean
local function stage_targets(is_visual)
  local targets, used_marks = resolve_targets(is_visual)
  local paths = collect_paths(targets)
  if #paths == 0 then
    return
  end

  local args = { 'add', '--' }
  vim.list_extend(args, paths)
  git_async(state.root, args, function(res)
    if res.code ~= 0 then
      vim.notify('git add failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    if used_marks then
      state.marked = {}
    end
    M.refresh()
  end)
end

---@param is_visual boolean
local function unstage_targets(is_visual)
  local targets, used_marks = resolve_targets(is_visual)
  local paths = collect_paths(targets)
  if #paths == 0 then
    return
  end

  local has_head = git_sync(state.root, { 'rev-parse', '--verify', 'HEAD' }).code == 0
  local args = has_head and { 'restore', '--staged', '--' } or { 'rm', '--cached', '-q', '--' }
  vim.list_extend(args, paths)

  git_async(state.root, args, function(res)
    if res.code ~= 0 then
      vim.notify('git unstage failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    if used_marks then
      state.marked = {}
    end
    M.refresh()
  end)
end

---@param root string
---@param rev_path string
---@param on_done fun(lines: string[])
local function git_show_lines_async(root, rev_path, on_done)
  git_async(root, { 'show', rev_path }, function(res)
    if res.code ~= 0 or not res.stdout or res.stdout == '' then
      on_done({})
      return
    end
    local lines = vim.split(res.stdout, '\n', { plain = true })
    if lines[#lines] == '' then
      table.remove(lines, #lines)
    end
    on_done(lines)
  end)
end

---@param lines string[]
---@param title string
---@param ft string|nil
---@return integer
local function create_scratch_buf(lines, title, ft)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'wipe'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  if ft and ft ~= '' then
    vim.bo[buf].filetype = ft
  end
  pcall(vim.api.nvim_buf_set_name, buf, title)
  return buf
end

---@param entry table
---@param reuse_current_tab boolean|nil
local function open_diff(entry, reuse_current_tab)
  local root = state.root
  local path = entry.path
  local orig_path = entry.orig_path or path
  local ft = vim.filetype.match({ filename = path })

  -- Find entry index for ]f / [f navigation
  for idx, e in ipairs(state.entries) do
    if e.key == entry.key then
      state.diff_tab_idx = idx
      break
    end
  end

  state.diff_gen = state.diff_gen + 1
  local gen = state.diff_gen

  local left_rev = nil
  local left_title
  local right_rev = nil
  local right_buf = nil
  local right_title

  if entry.section == 'staged' then
    left_rev = 'HEAD:' .. orig_path
    left_title = string.format('git://HEAD/%s', orig_path)
    right_rev = ':0:' .. path
    right_title = string.format('git://INDEX/%s', path)
  else
    if entry.code == '??' or entry.code == 'A' then
      left_title = string.format('git://EMPTY/%s', path)
    else
      left_rev = ':0:' .. orig_path
      left_title = string.format('git://INDEX/%s', orig_path)
    end

    local full_path = root .. '/' .. path
    if entry.code ~= 'D' and vim.fn.filereadable(full_path) == 1 then
      right_buf = vim.fn.bufadd(full_path)
    else
      right_title = string.format('git://DELETED/%s', path)
    end
  end

  local right_is_real = right_buf ~= nil
  if reuse_current_tab then
    vim.cmd('only')
  else
    vim.cmd('tabnew')
  end

  local left_win = vim.api.nvim_get_current_win()
  local left_buf = create_scratch_buf(left_rev and { 'Loading...' } or {}, left_title, ft)
  vim.api.nvim_win_set_buf(left_win, left_buf)

  vim.cmd('rightbelow vsplit')
  local right_win = vim.api.nvim_get_current_win()
  if right_buf then
    vim.fn.bufload(right_buf)
    vim.api.nvim_win_set_buf(right_win, right_buf)
  else
    right_buf = create_scratch_buf(right_rev and { 'Loading...' } or {}, right_title, ft)
    vim.api.nvim_win_set_buf(right_win, right_buf)
  end

  vim.api.nvim_set_current_win(left_win)
  vim.cmd('diffthis')
  vim.api.nvim_set_current_win(right_win)
  vim.cmd('diffthis')

  local function populate_buf(buf, lines)
    if gen ~= state.diff_gen or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false
    if vim.api.nvim_win_is_valid(left_win) then
      vim.api.nvim_win_call(left_win, function()
        vim.cmd('diffupdate')
      end)
    end
  end

  if left_rev then
    git_show_lines_async(root, left_rev, function(lines)
      populate_buf(left_buf, lines)
    end)
  end

  if right_rev then
    git_show_lines_async(root, right_rev, function(lines)
      populate_buf(right_buf, lines)
    end)
  end

  local function cleanup_real_buf_maps()
    if right_is_real and vim.api.nvim_buf_is_valid(right_buf) then
      pcall(vim.keymap.del, 'n', 'q', { buffer = right_buf })
      pcall(vim.keymap.del, 'n', ']f', { buffer = right_buf })
      pcall(vim.keymap.del, 'n', '[f', { buffer = right_buf })
    end
  end

  local function close_diff_tab()
    cleanup_real_buf_maps()
    if vim.fn.tabpagenr('$') > 1 then
      vim.cmd('tabclose')
    else
      vim.cmd('diffoff!')
      vim.cmd('only')
    end
  end

  local function step_diff(delta)
    if #state.entries == 0 or not state.diff_tab_idx then
      return
    end
    cleanup_real_buf_maps()
    local next_idx = ((state.diff_tab_idx - 1 + delta) % #state.entries) + 1
    open_diff(state.entries[next_idx], true)
  end

  for _, b in ipairs({ left_buf, right_buf }) do
    vim.keymap.set('n', 'q', close_diff_tab, { buffer = b, silent = true, desc = 'GitDiff: close tab' })
    vim.keymap.set('n', ']f', function() step_diff(1) end, { buffer = b, silent = true, desc = 'GitDiff: next file' })
    vim.keymap.set('n', '[f', function() step_diff(-1) end, { buffer = b, silent = true, desc = 'GitDiff: prev file' })
  end
end

---@param buf integer
local function setup_keymaps(buf)
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end

  map('n', ',', function() toggle_mark(false) end, 'GitStatus: toggle mark')
  map('x', ',', function() toggle_mark(true) end, 'GitStatus: toggle mark (visual)')

  map('n', '<<', function() stage_targets(false) end, 'GitStatus: stage')
  map('x', '<', function() stage_targets(true) end, 'GitStatus: stage (visual)')

  map('n', '>>', function() unstage_targets(false) end, 'GitStatus: unstage')
  map('x', '>', function() unstage_targets(true) end, 'GitStatus: unstage (visual)')

  map('n', '<CR>', function()
    local l = vim.api.nvim_win_get_cursor(0)[1]
    local e = state.line_entries[l]
    if e then
      open_diff(e, false)
    end
  end, 'GitStatus: open diffthis')

  map('n', 'r', M.refresh, 'GitStatus: refresh')
  map('n', 'q', function()
    if vim.fn.winnr('$') > 1 then
      vim.cmd('close')
    else
      vim.cmd('bwipeout')
    end
  end, 'GitStatus: close')

  map('n', '<Space>gc', function()
    vim.cmd('Commit')
  end, 'Git: commit via guise')

  map('n', '<Space>gp', function()
    vim.notify('Git push 開始...', vim.log.levels.INFO)
    vim.fn.jobstart({ 'git', '-C', state.root, 'push' }, {
      on_exit = function(_, code)
        if code == 0 then
          vim.notify('Git push done', vim.log.levels.INFO)
        else
          vim.notify('Git push fail (code: ' .. code .. ')', vim.log.levels.ERROR)
        end
      end,
    })
  end, 'Git: push')
end

---@return boolean
function M.is_open()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_is_loaded(state.buf)
end

---@param opts? { buf?: integer, root?: string }
function M.open(opts)
  opts = opts or {}
  local root = opts.root
  if not root or root == '' then
    local cur_path = vim.api.nvim_buf_get_name(0)
    if cur_path == '' or cur_path:match('^git%-status://') then
      cur_path = vim.fn.getcwd()
    end
    root = get_repo_root(cur_path)
  end
  if not root then
    vim.notify('Not inside a git repository', vim.log.levels.WARN)
    return
  end

  if state.root ~= root then
    state.marked = {}
  end
  state.root = root

  local buf_name = 'git-status://' .. root

  if opts.buf and vim.api.nvim_buf_is_valid(opts.buf) then
    state.buf = opts.buf
    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'wipe'
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = 'my-git-status'
    setup_keymaps(state.buf)
  elseif not state.buf or not vim.api.nvim_buf_is_valid(state.buf) or not vim.api.nvim_buf_is_loaded(state.buf) then
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
    end
    local existing = vim.fn.bufnr('^' .. vim.fn.escape(buf_name, '.*[]^$') .. '$')
    if existing ~= -1 and vim.api.nvim_buf_is_valid(existing) then
      pcall(vim.api.nvim_buf_delete, existing, { force = true })
    end
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'wipe'
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = 'my-git-status'
    pcall(vim.api.nvim_buf_set_name, state.buf, buf_name)
    setup_keymaps(state.buf)
  end

  local win = vim.fn.bufwinid(state.buf)
  if win ~= -1 then
    vim.api.nvim_set_current_win(win)
  else
    vim.api.nvim_win_set_buf(0, state.buf)
  end

  M.refresh()
end

return M
