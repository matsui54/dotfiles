local M = {}

local diff_gen = 0

---@param path string|nil
---@return string|nil
function M.find_git_root(path)
  local dir
  if type(path) == 'string' and path ~= '' and not path:match('^%a[%w+.-]*://') then
    dir = vim.fn.isdirectory(path) == 1 and path or vim.fn.fnamemodify(path, ':h')
  end
  if not dir or dir == '' or vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  local res = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if res.code ~= 0 or not res.stdout then
    return nil
  end
  return vim.trim(res.stdout)
end

---@param git_args string[]
---@return string
function M.format_git_cmd(git_args)
  local parts = { 'git' }
  for _, arg in ipairs(git_args) do
    local s = tostring(arg)
    if s:match('^[%w%._/%-%+=:@]+$') then
      parts[#parts + 1] = s
    else
      parts[#parts + 1] = vim.fn.shellescape(s)
    end
  end
  return table.concat(parts, ' ')
end

---@param res vim.SystemCompleted
---@return string
function M.trim_output(res)
  local err = vim.trim(res.stderr or '')
  if err ~= '' then
    return err
  end
  return vim.trim(res.stdout or '')
end

---@param root string|nil
---@param git_args string[]
---@param cb fun(res: vim.SystemCompleted)
---@param opts? { text?: boolean }
function M.run_git(root, git_args, cb, opts)
  local cmd = { 'git' }
  if root and root ~= '' then
    vim.list_extend(cmd, { '-C', root })
  end
  vim.list_extend(cmd, git_args)
  local text = not (opts and opts.text == false)
  vim.system(cmd, { text = text }, function(res)
    vim.schedule(function()
      cb(res)
    end)
  end)
end

---@param root string|nil
---@param git_args string[]
---@param opts? { text?: boolean }
---@return vim.SystemCompleted
function M.run_git_sync(root, git_args, opts)
  local cmd = { 'git' }
  if root and root ~= '' then
    vim.list_extend(cmd, { '-C', root })
  end
  vim.list_extend(cmd, git_args)
  local text = not (opts and opts.text == false)
  return vim.system(cmd, { text = text }):wait()
end

---@param ctx table
---@param cmds string[][]
---@param extra_note? string
---@return boolean
function M.confirm_git_cmds(ctx, cmds, extra_note)
  local cmd_strs = {}
  for _, args in ipairs(cmds) do
    cmd_strs[#cmd_strs + 1] = M.format_git_cmd(args)
  end

  local msg
  if #cmd_strs == 1 then
    msg = 'Run: ' .. cmd_strs[1]
  else
    msg = 'Run:\n  ' .. table.concat(cmd_strs, '\n  ')
  end
  if extra_note and extra_note ~= '' then
    msg = msg .. '\n\n' .. extra_note
  end

  local choice = ctx.with_prompt(function()
    return vim.fn.confirm(msg, '&Yes\n&No', 2)
  end)
  return choice == 1
end

---@param preferred string
---@param fallback string
---@return string
local function resolve_diff_hl(preferred, fallback)
  local ok, hl = pcall(vim.api.nvim_get_hl, 0, { name = preferred, link = false })
  if ok and type(hl) == 'table' and (hl.bg ~= nil or hl.fg ~= nil or hl.ctermbg ~= nil or hl.ctermfg ~= nil) then
    return preferred
  end
  return fallback
end

---@param lines string[]
---@param start_idx? integer
---@param out? table[]
---@return table[]
local function append_diff_highlights(lines, start_idx, out)
  local add_hl = resolve_diff_hl('diffAdded', 'DiffAdd')
  local del_hl = resolve_diff_hl('diffRemoved', 'DiffDelete')
  local hls = out or {}
  for i = start_idx or 1, #lines do
    local line = lines[i]
    local row = i - 1
    if vim.startswith(line, 'diff --git ')
      or vim.startswith(line, '--- ')
      or vim.startswith(line, '+++ ') then
      hls[#hls + 1] = { row = row, col_start = 0, col_end = -1, hl_group = 'Title' }
    elseif vim.startswith(line, 'index ')
      or vim.startswith(line, 'new file mode')
      or vim.startswith(line, 'deleted file mode')
      or vim.startswith(line, 'old mode')
      or vim.startswith(line, 'new mode')
      or vim.startswith(line, 'rename from ')
      or vim.startswith(line, 'rename to ')
      or vim.startswith(line, 'similarity index')
      or vim.startswith(line, 'Binary files ') then
      hls[#hls + 1] = { row = row, col_start = 0, col_end = -1, hl_group = 'Comment' }
    elseif vim.startswith(line, '@@ ') then
      hls[#hls + 1] = { row = row, col_start = 0, col_end = -1, hl_group = 'Special' }
    elseif vim.startswith(line, '+') then
      hls[#hls + 1] = { row = row, line_hl = add_hl }
    elseif vim.startswith(line, '-') then
      hls[#hls + 1] = { row = row, line_hl = del_hl }
    end
  end
  return hls
end

---@param lines string[]
---@return table[]
function M.highlight_diff_lines(lines)
  return append_diff_highlights(lines, 1, {})
end

---@param lines string[]
---@return table[]
function M.highlight_commit_show_lines(lines)
  local hls = {}
  local diff_start = nil
  for i, line in ipairs(lines) do
    if vim.startswith(line, 'diff --git ') then
      diff_start = i
      break
    end
    local row = i - 1
    if vim.startswith(line, 'commit ') then
      hls[#hls + 1] = { row = row, col_start = 0, col_end = -1, hl_group = 'Title' }
    elseif vim.startswith(line, 'Author:')
      or vim.startswith(line, 'AuthorDate:')
      or vim.startswith(line, 'Commit:')
      or vim.startswith(line, 'CommitDate:')
      or vim.startswith(line, 'Merge:') then
      hls[#hls + 1] = { row = row, col_start = 0, col_end = -1, hl_group = 'Type' }
    end
  end
  if diff_start then
    append_diff_highlights(lines, diff_start, hls)
  end
  return hls
end

---@param root string
---@param rev_path string
---@param on_done fun(lines: string[])
local function git_show_lines_async(root, rev_path, on_done)
  M.run_git(root, { 'show', rev_path }, function(res)
    if res.code ~= 0 or not res.stdout or res.stdout == '' then
      on_done({})
      return
    end
    local lines = vim.split(res.stdout, '\n', { plain = true })
    if lines[#lines] == '' then
      table.remove(lines, #lines)
    end
    on_done(lines)
  end, { text = false })
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

---@param ref string
---@return string
local function short_ref_label(ref)
  local hex, suffix = ref:match('^(%x+)(.*)$')
  if hex and #hex > 7 then
    return hex:sub(1, 7) .. suffix
  end
  return ref
end

---@param root string
---@param spec { ft?: string, left_rev?: string, left_title: string, right_rev?: string, right_buf?: integer, right_title?: string }
---@param step_cb? fun(delta: integer, cleanup: fun())
---@param reuse_current_tab? boolean
local function open_diff_tab_core(root, spec, step_cb, reuse_current_tab)
  diff_gen = diff_gen + 1
  local gen = diff_gen

  local right_buf = spec.right_buf
  local right_is_real = right_buf ~= nil
  if reuse_current_tab then
    vim.cmd('only')
  else
    vim.cmd('tabnew')
  end

  local left_win = vim.api.nvim_get_current_win()
  local left_buf = create_scratch_buf(spec.left_rev and { 'Loading...' } or {}, spec.left_title, spec.ft)
  vim.api.nvim_win_set_buf(left_win, left_buf)

  vim.cmd('rightbelow vsplit')
  local right_win = vim.api.nvim_get_current_win()
  if right_buf then
    vim.fn.bufload(right_buf)
    vim.api.nvim_win_set_buf(right_win, right_buf)
  else
    right_buf = create_scratch_buf(spec.right_rev and { 'Loading...' } or {}, spec.right_title or '', spec.ft)
    vim.api.nvim_win_set_buf(right_win, right_buf)
  end

  vim.api.nvim_set_current_win(left_win)
  vim.cmd('diffthis')
  vim.api.nvim_set_current_win(right_win)
  vim.cmd('diffthis')

  local function populate_buf(buf, lines)
    if gen ~= diff_gen or not vim.api.nvim_buf_is_valid(buf) then
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

  if spec.left_rev then
    git_show_lines_async(root, spec.left_rev, function(lines)
      populate_buf(left_buf, lines)
    end)
  end

  if spec.right_rev then
    git_show_lines_async(root, spec.right_rev, function(lines)
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
    if step_cb then
      step_cb(delta, cleanup_real_buf_maps)
    end
  end

  for _, b in ipairs({ left_buf, right_buf }) do
    vim.keymap.set('n', 'q', close_diff_tab, { buffer = b, silent = true, desc = 'GitDiff: close tab' })
    vim.keymap.set('n', ']f', function() step_diff(1) end, { buffer = b, silent = true, desc = 'GitDiff: next file' })
    vim.keymap.set('n', '[f', function() step_diff(-1) end, { buffer = b, silent = true, desc = 'GitDiff: prev file' })
  end
end

---@param root string
---@param entry table
---@param entries table[]
---@param reuse_current_tab boolean|nil
function M.open_status_diff_tab(root, entry, entries, reuse_current_tab)
  local path = entry.rel_path or entry.path
  local orig_path = entry.orig_path or path
  local ft = vim.filetype.match({ filename = path })

  local diff_idx = nil
  for idx, e in ipairs(entries or {}) do
    if e.key == entry.key then
      diff_idx = idx
      break
    end
  end

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

  open_diff_tab_core(root, {
    ft = ft,
    left_rev = left_rev,
    left_title = left_title,
    right_rev = right_rev,
    right_buf = right_buf,
    right_title = right_title,
  }, function(delta, cleanup)
    if not entries or #entries == 0 or not diff_idx then
      return
    end
    cleanup()
    local next_idx = ((diff_idx - 1 + delta) % #entries) + 1
    M.open_status_diff_tab(root, entries[next_idx], entries, true)
  end, reuse_current_tab)
end

---@param root string
---@param base_ref string|nil
---@param target_ref string|nil -- 'WORKTREE' for working tree file
---@param file table
---@param files_list table[]
---@param reuse_current_tab boolean|nil
function M.open_commit_diff_tab(root, base_ref, target_ref, file, files_list, reuse_current_tab)
  local path = file.rel_path or file.path
  local orig_path = file.orig_path or path
  local ft = vim.filetype.match({ filename = path })

  local diff_idx = nil
  for idx, f in ipairs(files_list or {}) do
    local fp = f.rel_path or f.path
    if fp == path then
      diff_idx = idx
      break
    end
  end

  local left_rev = nil
  local left_title
  if base_ref and file.code ~= 'A' then
    left_rev = base_ref .. ':' .. orig_path
    left_title = string.format('git://%s/%s', short_ref_label(base_ref), orig_path)
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
    right_title = string.format('git://%s/%s', short_ref_label(target_ref), path)
  else
    right_title = string.format('git://DELETED/%s', path)
  end

  open_diff_tab_core(root, {
    ft = ft,
    left_rev = left_rev,
    left_title = left_title,
    right_rev = right_rev,
    right_buf = right_buf,
    right_title = right_title,
  }, function(delta, cleanup)
    if not files_list or #files_list == 0 or not diff_idx then
      return
    end
    cleanup()
    local next_idx = ((diff_idx - 1 + delta) % #files_list) + 1
    M.open_commit_diff_tab(root, base_ref, target_ref, files_list[next_idx], files_list, true)
  end, reuse_current_tab)
end

return M
