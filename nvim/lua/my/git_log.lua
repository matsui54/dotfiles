local M = {}

local ns = vim.api.nvim_create_namespace('my_git_log')

local PAGE_SIZE = 100

local state = {
  buf = nil,
  root = nil,
  branch = nil,
  origin_file = nil,   -- relative path of file where gnl was invoked
  filter_file = false, -- true when filtering by origin_file
  line_range = nil,    -- { l1, l2 } for visual -L mode
  limit = PAGE_SIZE,
  commits = {},        -- list of { hash, short, date, author, refs, subject, expanded, loading, files }
  line_items = {},     -- 1-based lnum -> { kind = 'commit'|'file'|'compare_file', commit?, file?, compare? }
  marked_order = {},   -- list of up to 2 commit hashes
  compare = nil,       -- { base, target, base_short, target_short, files, loading }
  loading = false,
  refresh_gen = 0,
  diff_gen = 0,
  diff_files = nil,
  diff_file_idx = nil,
}

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
---@param abs_path string|nil
---@return string|nil
local function to_rel_path(root, abs_path)
  if not abs_path or abs_path == '' then
    return nil
  end
  local norm_root = vim.fs.normalize(root)
  local norm_file = vim.fs.normalize(abs_path)
  if norm_file:sub(1, #norm_root + 1) == norm_root .. '/' then
    return norm_file:sub(#norm_root + 2)
  end
  return nil
end

---@param raw string
---@return table[]
local function parse_commits(raw)
  local commits = {}
  local records = vim.split(raw, '\x1e', { plain = true, trimempty = true })
  for _, rec in ipairs(records) do
    local fields = vim.split(rec, '\0', { plain = true })
    if #fields >= 6 then
      local hash = vim.trim(fields[1])
      if hash ~= '' then
        table.insert(commits, {
          hash = hash,
          short = fields[2],
          date = fields[3],
          author = fields[4],
          refs = vim.trim(fields[5]),
          subject = fields[6],
          expanded = false,
          loading = false,
          files = nil,
        })
      end
    end
  end
  return commits
end

---@param raw string
---@return table[]
local function parse_name_status(raw)
  local files = {}
  local items = vim.split(raw, '\0', { plain = true, trimempty = true })
  local i = 1
  while i <= #items do
    local code = items[i]
    local c1 = code:sub(1, 1)
    if (c1 == 'R' or c1 == 'C') and i + 2 <= #items then
      local orig_path = items[i + 1]
      local path = items[i + 2]
      table.insert(files, { code = c1, path = path, orig_path = orig_path })
      i = i + 3
    elseif i + 1 <= #items then
      local path = items[i + 1]
      table.insert(files, { code = c1, path = path, orig_path = nil })
      i = i + 2
    else
      break
    end
  end
  return files
end

---@param code string
---@return string
local function hl_for_code(code)
  local c = code:sub(1, 1)
  if c == 'A' then
    return 'DiffAdd'
  elseif c == 'D' then
    return 'DiffDelete'
  elseif c == 'M' or c == 'R' or c == 'C' then
    return 'DiffChange'
  end
  return 'Normal'
end

---@param hash string
---@return boolean
local function is_marked(hash)
  for _, h in ipairs(state.marked_order) do
    if h == hash then
      return true
    end
  end
  return false
end

local function render()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local win = vim.fn.bufwinid(buf)
  local prev_line = 1
  local prev_id = nil
  if win ~= -1 then
    prev_line = vim.api.nvim_win_get_cursor(win)[1]
    local item = state.line_items[prev_line]
    if item then
      if item.kind == 'commit' then
        prev_id = 'commit:' .. item.commit.hash
      elseif item.kind == 'file' then
        prev_id = 'file:' .. item.commit.hash .. ':' .. item.file.path
      elseif item.kind == 'compare_file' then
        prev_id = 'cmp:' .. item.file.path
      end
    end
  end

  local lines = {}
  local highlights = {}
  state.line_items = {}

  local function add_line(text, hl_group, col_start, col_end)
    table.insert(lines, text)
    local lnum = #lines - 1
    if hl_group then
      table.insert(highlights, { lnum, col_start or 0, col_end or -1, hl_group })
    end
    return #lines
  end

  local filter_label = 'all'
  if state.line_range and state.origin_file then
    filter_label = string.format('L%d-%d:%s', state.line_range[1], state.line_range[2], state.origin_file)
  elseif state.filter_file and state.origin_file then
    filter_label = state.origin_file
  end

  local header = string.format('Repo: %s  [%s]  (%s)', state.root or '', state.branch or '...', filter_label)
  if state.loading then
    local lnum_1 = add_line(header .. '  (Loading...)')
    table.insert(highlights, { lnum_1 - 1, 0, #header, 'Title' })
    table.insert(highlights, { lnum_1 - 1, #header + 2, -1, 'Comment' })
  else
    add_line(header, 'Title')
  end

  -- Optional 2-commit / working-tree compare section
  if state.compare then
    add_line('')
    local cmp_title = string.format('Diff: %s..%s', state.compare.base_short, state.compare.target_short)
    if state.compare.loading then
      add_line(cmp_title .. '  (Loading...)', 'Title')
    else
      add_line(cmp_title, 'Title')
      for _, f in ipairs(state.compare.files or {}) do
        local display = f.orig_path and (f.orig_path .. ' -> ' .. f.path) or f.path
        local lnum_1 = add_line(string.format('  %s  %s', f.code, display))
        state.line_items[lnum_1] = { kind = 'compare_file', file = f, compare = state.compare }
        table.insert(highlights, { lnum_1 - 1, 2, 3, hl_for_code(f.code) })
      end
      if #(state.compare.files or {}) == 0 then
        add_line('  (no differences)', 'Comment')
      end
    end
  end

  add_line('')
  if #state.commits == 0 and not state.loading then
    add_line('  (no commits)', 'Comment')
  end

  for _, c in ipairs(state.commits) do
    local mark = is_marked(c.hash) and '*' or ' '
    local refs_str = (c.refs ~= '') and (' ' .. c.refs) or ''
    local text = string.format('%s %s  %s  %s%s  %s', mark, c.short, c.date, c.author, refs_str, c.subject)
    local lnum_1 = add_line(text)
    state.line_items[lnum_1] = { kind = 'commit', commit = c }

    local lnum_0 = lnum_1 - 1
    if mark == '*' then
      table.insert(highlights, { lnum_0, 0, 1, 'DiagnosticWarn' })
    end
    local hash_start = 2
    local hash_end = hash_start + #c.short
    local date_start = hash_end + 2
    local date_end = date_start + #c.date
    local author_start = date_end + 2
    local author_end = author_start + #c.author
    table.insert(highlights, { lnum_0, hash_start, hash_end, 'Identifier' })
    table.insert(highlights, { lnum_0, date_start, date_end, 'Comment' })
    table.insert(highlights, { lnum_0, author_start, author_end, 'Type' })
    if refs_str ~= '' then
      local refs_start = author_end + 1
      local refs_end = refs_start + #c.refs
      table.insert(highlights, { lnum_0, refs_start, refs_end, 'Special' })
    end

    if c.expanded then
      if c.loading then
        add_line('    (Loading files...)', 'Comment')
      elseif c.files and #c.files > 0 then
        for _, f in ipairs(c.files) do
          local display = f.orig_path and (f.orig_path .. ' -> ' .. f.path) or f.path
          local flnum_1 = add_line(string.format('    %s  %s', f.code, display))
          state.line_items[flnum_1] = { kind = 'file', commit = c, file = f }
          table.insert(highlights, { flnum_1 - 1, 4, 5, hl_for_code(f.code) })
        end
      else
        add_line('    (no changed files)', 'Comment')
      end
    end
  end

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

  if win ~= -1 and vim.api.nvim_win_is_valid(win) then
    local target_line = nil
    if prev_id then
      for lnum, item in pairs(state.line_items) do
        local id
        if item.kind == 'commit' then
          id = 'commit:' .. item.commit.hash
        elseif item.kind == 'file' then
          id = 'file:' .. item.commit.hash .. ':' .. item.file.path
        elseif item.kind == 'compare_file' then
          id = 'cmp:' .. item.file.path
        end
        if id == prev_id then
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

  local args = {
    'log',
    '--max-count=' .. tostring(state.limit),
    '--date=short',
    '--format=%H%x00%h%x00%ad%x00%an%x00%d%x00%s%x1e',
  }
  if state.line_range and state.origin_file then
    table.insert(args, '--no-patch')
    table.insert(args, string.format('-L%d,%d:%s', state.line_range[1], state.line_range[2], state.origin_file))
  elseif state.filter_file and state.origin_file then
    table.insert(args, '--')
    table.insert(args, state.origin_file)
  end

  git_async(state.root, args, function(res)
    if gen ~= state.refresh_gen then
      return
    end
    state.loading = false
    if res.code ~= 0 then
      render()
      vim.notify('git log failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    state.commits = parse_commits(res.stdout or '')
    render()
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

---@param base_ref string|nil
---@param target_ref string|nil -- 'WORKTREE' for working tree file
---@param file table
---@param files_list table[]
---@param reuse_current_tab boolean|nil
local function open_diff(base_ref, target_ref, file, files_list, reuse_current_tab)
  local root = state.root
  local path = file.path
  local orig_path = file.orig_path or path
  local ft = vim.filetype.match({ filename = path })

  state.diff_files = files_list
  state.diff_file_idx = nil
  for idx, f in ipairs(files_list or {}) do
    if f.path == path then
      state.diff_file_idx = idx
      break
    end
  end

  state.diff_gen = state.diff_gen + 1
  local gen = state.diff_gen

  local left_rev = nil
  local left_title
  if base_ref and file.code ~= 'A' then
    left_rev = base_ref .. ':' .. orig_path
    left_title = string.format('git://%s/%s', base_ref:sub(1, 7), orig_path)
  else
    left_title = string.format('git://EMPTY/%s', orig_path)
  end

  local right_rev = nil
  local right_buf = nil
  local right_title
  if target_ref == 'WORKTREE' then
    local full_path = root .. '/' .. path
    if file.code ~= 'D' and vim.fn.filereadable(full_path) == 1 then
      right_buf = vim.fn.bufadd(full_path)
    else
      right_title = string.format('git://DELETED/%s', path)
    end
  elseif target_ref and file.code ~= 'D' then
    right_rev = target_ref .. ':' .. path
    right_title = string.format('git://%s/%s', target_ref:sub(1, 7), path)
  else
    right_title = string.format('git://DELETED/%s', path)
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
    if not state.diff_files or #state.diff_files == 0 or not state.diff_file_idx then
      return
    end
    cleanup_real_buf_maps()
    local next_idx = ((state.diff_file_idx - 1 + delta) % #state.diff_files) + 1
    open_diff(base_ref, target_ref, state.diff_files[next_idx], state.diff_files, true)
  end

  for _, b in ipairs({ left_buf, right_buf }) do
    vim.keymap.set('n', 'q', close_diff_tab, { buffer = b, silent = true, desc = 'GitLogDiff: close tab' })
    vim.keymap.set('n', ']f', function() step_diff(1) end, { buffer = b, silent = true, desc = 'GitLogDiff: next file' })
    vim.keymap.set('n', '[f', function() step_diff(-1) end, { buffer = b, silent = true, desc = 'GitLogDiff: prev file' })
  end
end

---@param commit table
local function toggle_commit_expand(commit)
  if commit.expanded then
    commit.expanded = false
    render()
    return
  end

  commit.expanded = true
  if commit.files then
    render()
    return
  end

  commit.loading = true
  render()
  git_async(state.root, { 'diff-tree', '--no-commit-id', '--name-status', '-r', '-z', '--root', commit.hash }, function(res)
    commit.loading = false
    if res.code ~= 0 then
      commit.files = {}
      render()
      vim.notify('git diff-tree failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    commit.files = parse_name_status(res.stdout or '')
    render()
  end)
end

local function toggle_mark()
  local l = vim.api.nvim_win_get_cursor(0)[1]
  local item = state.line_items[l]
  if not item or item.kind ~= 'commit' then
    return
  end
  local hash = item.commit.hash
  for idx, h in ipairs(state.marked_order) do
    if h == hash then
      table.remove(state.marked_order, idx)
      render()
      return
    end
  end
  if #state.marked_order >= 2 then
    table.remove(state.marked_order, 1)
  end
  table.insert(state.marked_order, hash)
  render()
end

local function run_compare()
  if #state.marked_order == 0 then
    if state.compare then
      state.compare = nil
      render()
    else
      vim.notify('Mark 1 or 2 commits with "," first', vim.log.levels.INFO)
    end
    return
  end

  local base, target, base_short, target_short
  if #state.marked_order == 1 then
    base = state.marked_order[1]
    target = 'WORKTREE'
    base_short = base:sub(1, 7)
    target_short = 'WORKTREE'
  else
    local h1, h2 = state.marked_order[1], state.marked_order[2]
    local idx1, idx2 = 0, 0
    for i, c in ipairs(state.commits) do
      if c.hash == h1 then idx1 = i end
      if c.hash == h2 then idx2 = i end
    end
    if idx1 > idx2 then
      base, target = h1, h2
    else
      base, target = h2, h1
    end
    base_short = base:sub(1, 7)
    target_short = target:sub(1, 7)
  end

  state.compare = {
    base = base,
    target = target,
    base_short = base_short,
    target_short = target_short,
    loading = true,
    files = nil,
  }
  render()

  local args = { 'diff', '--name-status', '-z', base }
  if target ~= 'WORKTREE' then
    table.insert(args, target)
  end

  git_async(state.root, args, function(res)
    if not state.compare or state.compare.base ~= base or state.compare.target ~= target then
      return
    end
    state.compare.loading = false
    if res.code ~= 0 then
      state.compare.files = {}
      render()
      vim.notify('git diff failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
      return
    end
    state.compare.files = parse_name_status(res.stdout or '')
    render()
  end)
end

---@param commit table
local function show_commit_popup(commit)
  git_async(state.root, { 'show', '--stat', '--format=fuller', commit.hash }, function(res)
    if res.code ~= 0 or not res.stdout then
      vim.notify('git show failed', vim.log.levels.ERROR)
      return
    end
    local lines = vim.split(res.stdout, '\n', { plain = true })
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].buftype = 'nofile'
    vim.bo[buf].bufhidden = 'wipe'
    vim.bo[buf].modifiable = false
    vim.bo[buf].filetype = 'git'

    local width = math.min(math.floor(vim.o.columns * 0.8), 100)
    local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.7))
    local win = vim.api.nvim_open_win(buf, true, {
      relative = 'editor',
      width = width,
      height = height,
      row = math.floor((vim.o.lines - height) / 2),
      col = math.floor((vim.o.columns - width) / 2),
      style = 'minimal',
      border = 'rounded',
      title = ' ' .. commit.short .. ' ',
      title_pos = 'center',
    })
    local close = function()
      if vim.api.nvim_win_is_valid(win) then
        vim.api.nvim_win_close(win, true)
      end
    end
    vim.keymap.set('n', 'q', close, { buffer = buf, silent = true })
    vim.keymap.set('n', '<Esc>', close, { buffer = buf, silent = true })
  end)
end

---@param buf integer
local function setup_keymaps(buf)
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, desc = desc })
  end

  local function activate()
    local l = vim.api.nvim_win_get_cursor(0)[1]
    local item = state.line_items[l]
    if not item then
      return
    end
    if item.kind == 'commit' then
      toggle_commit_expand(item.commit)
    elseif item.kind == 'file' then
      open_diff(item.commit.hash .. '^', item.commit.hash, item.file, item.commit.files, false)
    elseif item.kind == 'compare_file' then
      open_diff(item.compare.base, item.compare.target, item.file, item.compare.files, false)
    end
  end

  map('n', '<CR>', activate, 'GitLog: expand commit or open diff')
  map('n', '<Tab>', activate, 'GitLog: expand commit or open diff')
  map('n', ',', toggle_mark, 'GitLog: mark commit (up to 2)')
  map('n', 'd', run_compare, 'GitLog: compare marked commits')
  map('n', 'c', function()
    state.marked_order = {}
    state.compare = nil
    render()
  end, 'GitLog: clear marks & compare')

  map('n', 'K', function()
    local l = vim.api.nvim_win_get_cursor(0)[1]
    local item = state.line_items[l]
    if item and item.commit then
      show_commit_popup(item.commit)
    end
  end, 'GitLog: show commit details')

  map('n', 'y', function()
    local l = vim.api.nvim_win_get_cursor(0)[1]
    local item = state.line_items[l]
    if item and item.commit then
      vim.fn.setreg('"', item.commit.hash)
      pcall(vim.fn.setreg, '+', item.commit.hash)
      vim.notify('Copied ' .. item.commit.short, vim.log.levels.INFO)
    end
  end, 'GitLog: yank commit hash')

  map('n', 'F', function()
    if not state.origin_file then
      vim.notify('No origin file to filter by', vim.log.levels.INFO)
      return
    end
    state.line_range = nil
    state.filter_file = not state.filter_file
    M.refresh()
  end, 'GitLog: toggle current file filter')

  map('n', '+', function()
    state.limit = state.limit + PAGE_SIZE
    M.refresh()
  end, 'GitLog: load more commits')

  map('n', 'r', M.refresh, 'GitLog: refresh')
  map('n', 'q', function()
    if vim.fn.winnr('$') > 1 then
      vim.cmd('close')
    else
      vim.cmd('bwipeout')
    end
  end, 'GitLog: close')
end

---@return boolean
function M.is_open()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf) and vim.api.nvim_buf_is_loaded(state.buf)
end

---@param opts? { buf?: integer, root?: string, file?: string, line_range?: integer[] }
function M.open(opts)
  opts = opts or {}
  local cur_path = opts.file or vim.api.nvim_buf_get_name(0)
  local root = opts.root
  if not root or root == '' then
    local probe = cur_path
    if probe == '' or probe:match('^git%-log://') or probe:match('^git%-status://') then
      probe = vim.fn.getcwd()
    end
    root = get_repo_root(probe)
  end
  if not root then
    vim.notify('Not inside a git repository', vim.log.levels.WARN)
    return
  end

  if state.root ~= root then
    state.marked_order = {}
    state.compare = nil
    state.limit = PAGE_SIZE
  end
  state.root = root

  if not cur_path:match('^git%-log://') and not cur_path:match('^git%-status://') then
    local rel = to_rel_path(root, cur_path)
    if rel then
      state.origin_file = rel
    end
  end

  state.line_range = opts.line_range
  if state.line_range then
    state.filter_file = true
  elseif not opts.buf then
    state.filter_file = false
  end

  local buf_name = 'git-log://' .. root

  if opts.buf and vim.api.nvim_buf_is_valid(opts.buf) then
    state.buf = opts.buf
    vim.bo[state.buf].buftype = 'nofile'
    vim.bo[state.buf].bufhidden = 'wipe'
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = 'my-git-log'
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
    vim.bo[state.buf].filetype = 'my-git-log'
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
