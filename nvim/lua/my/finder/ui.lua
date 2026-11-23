local actions = require('my.finder.actions')
local preview = require('my.finder.preview')

local uv = vim.uv or vim.loop

local M = {}

local ns_list = vim.api.nvim_create_namespace('my_finder_list')
local ns_filter = vim.api.nvim_create_namespace('my_finder_filter')
local augroup = vim.api.nvim_create_augroup('my_finder_ui', { clear = true })

local MARK_PREFIX_WIDTH = 2 -- "* " or "  "
local DEFAULT_BUILTIN_ACTIONS = { 'open', 'vsplit', 'split', 'tabedit', 'qf' }

local function setup_highlights()
  vim.api.nvim_set_hl(0, 'MyFinderPrompt', { link = 'Special', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderMatch', { link = 'Special', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderMark', { link = 'DiagnosticWarn', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderCounter', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderHint', { link = 'Comment', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderGitDirty', { link = 'Changed', default = true })
  vim.api.nvim_set_hl(0, 'MyFinderGitNew', { link = 'Added', default = true })
end

local state = {
  active = false,
  closing = false,
  transitioning = false,
  source = nil,
  opts = {},
  ctx = {},

  filter_buf = nil,
  filter_win = nil,
  list_buf = nil,
  list_win = nil,
  preview_win = nil,

  preview_enabled = true,
  query = '',
  items = {},
  total_matched = 0,
  total_items = 0,
  scanning = false,
  has_more = false,
  marked = {},

  last_first_id = nil,
  last_cursor_id = nil,
  search_gen = 0,
  action_candidates = {},
  debounce_timer = nil,
  scan_poll_timer = nil,
  scan_poll_active = false,
}

local last_session = nil

---@param show_preview boolean
local function compute_layout(show_preview)
  local columns = vim.o.columns
  local lines = math.max(10, vim.o.lines - vim.o.cmdheight)

  if show_preview then
    local total_w = math.max(60, math.min(columns, math.floor(columns * 0.85)))
    local total_h = math.max(12, math.min(lines, math.floor(lines * 0.80)))
    local start_col = math.floor((columns - total_w) / 2)
    local start_row = math.floor((lines - total_h) / 2)

    local left_w = math.max(28, math.floor(total_w * 0.45))
    local right_w = math.max(20, total_w - left_w)

    return {
      filter = {
        row = start_row,
        col = start_col,
        width = left_w,
        height = 1,
      },
      list = {
        row = start_row + 1,
        col = start_col,
        width = left_w,
        height = math.max(4, total_h - 1),
      },
      preview = {
        row = start_row,
        col = start_col + left_w,
        width = right_w,
        height = total_h,
      },
    }
  end

  local total_w = math.max(40, math.min(columns, math.floor(columns * 0.65)))
  local total_h = math.max(10, math.min(lines, math.floor(lines * 0.75)))
  local start_col = math.floor((columns - total_w) / 2)
  local start_row = math.floor((lines - total_h) / 2)

  return {
    filter = {
      row = start_row,
      col = start_col,
      width = total_w,
      height = 1,
    },
    list = {
      row = start_row + 1,
      col = start_col,
      width = total_w,
      height = math.max(4, total_h - 1),
    },
    preview = nil,
  }
end

local function update_filter_virt_text()
  if not state.filter_buf or not vim.api.nvim_buf_is_valid(state.filter_buf) then
    return
  end
  vim.api.nvim_buf_clear_namespace(state.filter_buf, ns_filter, 0, -1)

  local prompt = (state.ctx and state.ctx.prompt) or (state.source and state.source.prompt) or '> '
  pcall(vim.api.nvim_buf_set_extmark, state.filter_buf, ns_filter, 0, 0, {
    virt_text = { { prompt, 'MyFinderPrompt' } },
    virt_text_pos = 'inline',
    right_gravity = false,
  })

  local total_str = state.has_more and (tostring(state.total_items) .. '+') or tostring(state.total_items)
  local status_str
  if state.scanning then
    status_str = string.format('%d / %s (scanning...)', state.total_matched, total_str)
  else
    status_str = string.format('%d / %s', state.total_matched, total_str)
  end

  pcall(vim.api.nvim_buf_set_extmark, state.filter_buf, ns_filter, 0, 0, {
    virt_text = { { status_str, 'MyFinderCounter' } },
    virt_text_pos = 'right_align',
  })
end

local function render_list(preserve_cursor)
  local buf = state.list_buf
  local win = state.list_win
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local prev_line = 1
  local prev_id = nil
  if preserve_cursor and win and vim.api.nvim_win_is_valid(win) then
    prev_line = vim.api.nvim_win_get_cursor(win)[1]
    if state.items[prev_line] then
      prev_id = state.items[prev_line].id
    end
  end

  local lines = {}
  local highlights = {}

  if #state.items == 0 then
    local hint = nil
    if state.scanning then
      hint = (state.source and state.source.scanning_hint) or '  Scanning files...'
    elseif state.query == '' and state.source and state.source.empty_hint then
      hint = state.source.empty_hint
    elseif state.source and state.source.no_match_hint then
      hint = state.source.no_match_hint
    else
      hint = '  (no matches)'
    end
    lines[1] = hint
    highlights[1] = { 0, 0, #hint, 'MyFinderHint' }
  else
    for i, item in ipairs(state.items) do
      local is_marked = state.marked[item.id] == true
      local prefix = is_marked and '* ' or '  '
      local text = item.display or ''
      local line_str = prefix .. text
      lines[i] = line_str
      local row = i - 1

      if is_marked then
        table.insert(highlights, { row, 0, 1, 'MyFinderMark' })
      end

      if item.highlights then
        for _, h in ipairs(item.highlights) do
          local s = MARK_PREFIX_WIDTH + (h[1] or 0)
          local e = MARK_PREFIX_WIDTH + (h[2] or 0)
          if e > s and e <= #line_str then
            table.insert(highlights, { row, s, e, h[3] })
          end
        end
      end

      if item.match_indices then
        local base_off = MARK_PREFIX_WIDTH + (item.match_offset or 0)
        for _, byte_idx in ipairs(item.match_indices) do
          local s = base_off + byte_idx
          if s >= base_off and s < #line_str then
            table.insert(highlights, { row, s, s + 1, 'MyFinderMatch' })
          end
        end
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  vim.api.nvim_buf_clear_namespace(buf, ns_list, 0, -1)
  for _, h in ipairs(highlights) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns_list, h[1], h[2], {
      end_col = h[3],
      hl_group = h[4],
      priority = 150,
    })
  end

  if win and vim.api.nvim_win_is_valid(win) then
    local target_line = 1
    if preserve_cursor and #state.items > 0 then
      local found = false
      if prev_id then
        for i, item in ipairs(state.items) do
          if item.id == prev_id then
            target_line = i
            found = true
            break
          end
        end
      end
      if not found then
        target_line = math.min(prev_line, #state.items)
      end
    end
    pcall(vim.api.nvim_win_set_cursor, win, { target_line, 0 })
  end

  update_filter_virt_text()
end

---@return table|nil
local function current_item()
  if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
    return nil
  end
  local lnum = vim.api.nvim_win_get_cursor(state.list_win)[1]
  return state.items[lnum]
end

---@return table[]
local function resolve_action_items()
  if next(state.marked) ~= nil then
    local out = {}
    for _, item in ipairs(state.items) do
      if state.marked[item.id] then
        table.insert(out, item)
      end
    end
    if #out > 0 then
      return out
    end
  end
  local cur = current_item()
  if cur then
    return { cur }
  end
  return {}
end

---@return table[]
local function resolve_visual_items()
  local l1 = vim.fn.line('v')
  local l2 = vim.fn.line('.')
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'nx', false)
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local out = {}
  for l = l1, l2 do
    local item = state.items[l]
    if item then
      out[#out + 1] = item
    end
  end
  return out
end

local function sync_preview(opts)
  opts = opts or {}
  if not state.preview_enabled or not state.preview_win or not vim.api.nvim_win_is_valid(state.preview_win) then
    return
  end
  local item = current_item()
  local cur_id = item and item.id or nil
  if not opts.force and cur_id == state.last_cursor_id then
    return
  end
  state.last_cursor_id = cur_id
  preview.schedule(state.preview_win, item, state.source, opts)
end

local start_scan_poll_if_needed

local function apply_search_results(res, opts)
  opts = opts or {}
  state.items = res.items or {}
  state.total_matched = res.total_matched or #state.items
  state.total_items = res.total_items or #state.items
  state.scanning = res.scanning == true
  state.has_more = res.has_more == true

  render_list(opts.preserve_cursor)

  local restore_id = opts.restore_cursor_id or res.restore_cursor_id
  local restore_line = opts.restore_cursor_line or res.restore_cursor_line
  if restore_id then
    local found = false
    local target_line = restore_line or 1
    for i, it in ipairs(state.items) do
      if it.id == restore_id then
        target_line = i
        found = true
        break
      end
    end
    if (found or restore_line ~= nil) and state.list_win and vim.api.nvim_win_is_valid(state.list_win) and #state.items > 0 then
      target_line = math.max(1, math.min(target_line, #state.items))
      pcall(vim.api.nvim_win_set_cursor, state.list_win, { target_line, 0 })
    end
  end

  local first_item = state.items[1]
  local new_first_id = first_item and first_item.id or nil
  local cur = current_item()
  local new_cur_id = cur and cur.id or nil
  local force_preview = opts.force_preview or res.force_preview

  if force_preview then
    state.last_first_id = new_first_id
    state.last_cursor_id = new_cur_id
    if state.preview_enabled and state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      preview.schedule(state.preview_win, cur, state.source, { force = true, immediate = opts.immediate_preview })
    end
  elseif new_cur_id ~= state.last_cursor_id then
    state.last_first_id = new_first_id
    state.last_cursor_id = new_cur_id
    if state.preview_enabled and state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      preview.schedule(state.preview_win, cur, state.source, { force = true })
    end
  end

  if state.scanning then
    if state.source and state.source.poll_scan then
      start_scan_poll_if_needed()
    end
  elseif state.scan_poll_active then
    state.scan_poll_active = false
    if state.scan_poll_timer then
      pcall(function()
        state.scan_poll_timer:stop()
      end)
    end
  end
end

local function run_search(opts)
  opts = opts or {}
  if not state.active or not state.source then
    return
  end

  state.search_gen = state.search_gen + 1
  local gen = state.search_gen

  local query = state.query
  local ctx = state.ctx

  if type(state.source.search) == 'function' then
    local sync_res = state.source.search(query, ctx, function(async_res)
      if not state.active or gen ~= state.search_gen then
        return
      end
      apply_search_results(async_res, opts)
    end, opts)
    if type(sync_res) == 'table' then
      apply_search_results(sync_res, opts)
    end
  end
end

local function stop_timers()
  state.scan_poll_active = false
  if state.debounce_timer then
    pcall(function()
      state.debounce_timer:stop()
    end)
  end
  if state.scan_poll_timer then
    pcall(function()
      state.scan_poll_timer:stop()
    end)
  end
end

function M.close(opts)
  opts = opts or {}
  if not state.active or state.closing then
    return
  end
  state.closing = true
  stop_timers()

  if opts.save_session ~= false and state.source and not state.source.no_resume then
    local cur = current_item()
    local cur_line = 1
    if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
      cur_line = vim.api.nvim_win_get_cursor(state.list_win)[1]
    end
    last_session = {
      source = state.source,
      opts = vim.deepcopy(state.opts),
      query = state.query,
      marked = vim.deepcopy(state.marked),
      cursor_id = cur and cur.id or nil,
      cursor_line = cur_line,
      preview_enabled = state.preview_enabled,
    }
  end

  local on_cancel = opts.on_cancel and state.ctx and state.ctx.on_cancel
  local on_close = state.source and state.source.on_close
  local close_ctx = state.ctx
  local origin_win = state.ctx and state.ctx.origin_win

  pcall(vim.api.nvim_clear_autocmds, { group = augroup })
  preview.reset()

  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == 'i' then
    pcall(vim.cmd, 'stopinsert')
  end

  for _, win in ipairs({ state.preview_win, state.filter_win, state.list_win }) do
    if win and vim.api.nvim_win_is_valid(win) then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
  for _, buf in ipairs({ state.filter_buf, state.list_buf }) do
    if buf and vim.api.nvim_buf_is_valid(buf) then
      pcall(vim.api.nvim_buf_delete, buf, { force = true })
    end
  end

  if origin_win and vim.api.nvim_win_is_valid(origin_win) then
    pcall(vim.api.nvim_set_current_win, origin_win)
  end

  state.active = false
  state.closing = false
  state.transitioning = false
  state.scanning = false
  state.has_more = false
  state.filter_buf = nil
  state.filter_win = nil
  state.list_buf = nil
  state.list_win = nil
  state.preview_win = nil
  state.items = {}
  state.action_candidates = {}
  state.source = nil
  state.ctx = {}

  if on_close then
    pcall(on_close, close_ctx)
  end

  if on_cancel then
    pcall(on_cancel)
  end
end

local function return_to_list_normal()
  if not state.active or state.closing then
    return
  end
  state.transitioning = true
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == 'i' then
    vim.cmd('stopinsert')
  end
  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    pcall(vim.api.nvim_set_current_win, state.list_win)
  end
  vim.schedule(function()
    state.transitioning = false
  end)
end

local function enter_filter_insert()
  if not state.active or state.closing then
    return
  end
  if not state.filter_win or not vim.api.nvim_win_is_valid(state.filter_win) then
    return
  end
  state.transitioning = true
  vim.api.nvim_set_current_win(state.filter_win)
  local line = vim.api.nvim_buf_get_lines(state.filter_buf, 0, 1, false)[1] or ''
  pcall(vim.api.nvim_win_set_cursor, state.filter_win, { 1, #line })
  vim.cmd('startinsert!')
  vim.schedule(function()
    state.transitioning = false
  end)
end

local function relayout()
  if not state.active or state.closing then
    return
  end
  local layout = compute_layout(state.preview_enabled)

  if state.filter_win and vim.api.nvim_win_is_valid(state.filter_win) then
    pcall(vim.api.nvim_win_set_config, state.filter_win, {
      relative = 'editor',
      row = layout.filter.row,
      col = layout.filter.col,
      width = layout.filter.width,
      height = layout.filter.height,
    })
  end

  if state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
    pcall(vim.api.nvim_win_set_config, state.list_win, {
      relative = 'editor',
      row = layout.list.row,
      col = layout.list.col,
      width = layout.list.width,
      height = layout.list.height,
    })
  end

  if state.preview_enabled and layout.preview then
    local pbuf = preview.ensure_buf()
    if state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
      pcall(vim.api.nvim_win_set_config, state.preview_win, {
        relative = 'editor',
        row = layout.preview.row,
        col = layout.preview.col,
        width = layout.preview.width,
        height = layout.preview.height,
      })
    else
      state.preview_win = vim.api.nvim_open_win(pbuf, false, {
        relative = 'editor',
        row = layout.preview.row,
        col = layout.preview.col,
        width = layout.preview.width,
        height = layout.preview.height,
        style = 'minimal',
        border = 'none',
        focusable = false,
        zindex = 50,
      })
      preview.apply_win_opts(state.preview_win)
    end
  elseif state.preview_win and vim.api.nvim_win_is_valid(state.preview_win) then
    pcall(vim.api.nvim_win_close, state.preview_win, true)
    state.preview_win = nil
  end
end

local function toggle_preview()
  if not state.active then
    return
  end
  if state.source and state.source.allow_preview == false then
    return
  end
  state.preview_enabled = not state.preview_enabled
  relayout()
  if state.preview_enabled then
    local cur = current_item()
    state.last_cursor_id = cur and cur.id or nil
    preview.schedule(state.preview_win, cur, state.source, { force = true, immediate = true })
  else
    preview.reset()
  end
end

---@param source table|nil
---@param kind string
---@return { fn: function, allow_empty: boolean, desc: string|nil }|nil
local function get_source_action(source, kind)
  if not source or type(source.actions) ~= 'table' then
    return nil
  end
  local spec = source.actions[kind]
  if type(spec) == 'function' then
    return { fn = spec, allow_empty = false }
  elseif type(spec) == 'table' and type(spec.fn) == 'function' then
    return {
      fn = spec.fn,
      allow_empty = spec.allow_empty == true,
      desc = spec.desc,
    }
  end
  return nil
end

---@param source table|nil
---@param kind string
---@return boolean
local function is_builtin_allowed(source, kind)
  local list = (source and source.builtin_actions) or DEFAULT_BUILTIN_ACTIONS
  for _, name in ipairs(list) do
    if name == kind then
      return true
    end
  end
  return false
end

---@param source table|nil
---@return string[]
local function list_available_actions(source)
  local seen = {}
  local out = {}
  local function add(name)
    if type(name) == 'string' and name ~= '' and not seen[name] then
      seen[name] = true
      out[#out + 1] = name
    end
  end

  if source and type(source.actions) == 'table' then
    for name in pairs(source.actions) do
      if get_source_action(source, name) then
        add(name)
      end
    end
  end

  local builtins = (source and source.builtin_actions) or DEFAULT_BUILTIN_ACTIONS
  for _, name in ipairs(builtins) do
    add(name)
  end

  table.sort(out)
  return out
end

function _G.MyFinderCompleteAction(arglead)
  local candidates = state.action_candidates or {}
  if not arglead or arglead == '' then
    return vim.deepcopy(candidates)
  end
  local lead = arglead:lower()
  local prefix = {}
  local substr = {}
  for _, name in ipairs(candidates) do
    local lower = name:lower()
    if vim.startswith(lower, lead) then
      prefix[#prefix + 1] = name
    elseif lower:find(lead, 1, true) then
      substr[#substr + 1] = name
    end
  end
  return vim.list_extend(prefix, substr)
end

---@param ctx table
local function bind_ctx_helpers(ctx)
  local session_ctx = ctx

  ctx.refresh = function(arg)
    if not state.active or state.ctx ~= session_ctx then
      return
    end
    local ropts = { preserve_cursor = true, force_preview = true }
    if type(arg) == 'table' then
      ropts = vim.tbl_extend('force', ropts, arg)
    elseif arg == false then
      ropts.preserve_cursor = false
    end
    run_search(ropts)
  end

  ctx.close = function()
    if state.active and state.ctx == session_ctx then
      M.close({ save_session = true })
    end
  end

  ctx.clear_marks = function(ids)
    if not state.active or state.ctx ~= session_ctx then
      return
    end
    if ids == nil then
      state.marked = {}
    else
      for _, id in ipairs(ids) do
        state.marked[id] = nil
      end
    end
  end

  ctx.get_marks = function()
    if not state.active or state.ctx ~= session_ctx then
      return {}
    end
    return vim.deepcopy(state.marked)
  end

  ctx.get_cursor_id = function()
    if not state.active or state.ctx ~= session_ctx then
      return nil
    end
    local cur = current_item()
    return cur and cur.id or nil
  end

  ctx.get_preview_enabled = function()
    return state.preview_enabled
  end

  ctx.with_prompt = function(fn, async_mode)
    if type(fn) ~= 'function' then
      return nil
    end
    local prev = state.transitioning
    state.transitioning = true
    local restored = false
    local function restore()
      if not restored then
        restored = true
        state.transitioning = prev
      end
    end
    local ok, res = pcall(fn, restore)
    if not ok then
      restore()
      local msg = tostring(res)
      if not msg:find('Keyboard interrupt', 1, true) then
        vim.notify(msg, vim.log.levels.ERROR)
      end
      return nil
    end
    if not async_mode then
      restore()
    end
    return res
  end
end

---@param kind string
---@param action_opts? { from_chooser?: boolean, visual?: boolean }
local function run_action(kind, action_opts)
  if not state.active or state.closing then
    return
  end

  local targets = (action_opts and action_opts.visual) and resolve_visual_items() or resolve_action_items()
  local source = state.source
  local ctx = state.ctx

  ctx.query = state.query
  ctx.title = (source and source.title) or 'Finder'

  local action_spec = get_source_action(source, kind)
  if action_spec then
    if #targets == 0 and not action_spec.allow_empty then
      if action_opts and action_opts.from_chooser then
        vim.notify('No target item for action: ' .. kind, vim.log.levels.WARN)
      end
      return
    end
    local keep_open = action_spec.fn(targets, ctx)
    if keep_open == 'keep_open' then
      return
    end
    M.close({ save_session = true })
    return
  end

  if not is_builtin_allowed(source, kind) then
    return
  end

  if #targets == 0 then
    if kind ~= 'qf' or #state.items == 0 then
      if action_opts and action_opts.from_chooser then
        vim.notify('No target item for action: ' .. kind, vim.log.levels.WARN)
      end
      return
    end
  end

  if kind == 'open' then
    if source and type(source.on_select) == 'function' then
      M.close({ save_session = true })
      source.on_select(targets, 'edit', ctx)
    else
      M.close({ save_session = true })
      actions.open_files(targets, 'edit', ctx)
    end
  elseif kind == 'vsplit' then
    if source and type(source.on_select) == 'function' then
      M.close({ save_session = true })
      source.on_select(targets, 'vsplit', ctx)
    else
      M.close({ save_session = true })
      actions.open_files(targets, 'vsplit', ctx)
    end
  elseif kind == 'split' then
    if source and type(source.on_select) == 'function' then
      M.close({ save_session = true })
      source.on_select(targets, 'split', ctx)
    else
      M.close({ save_session = true })
      actions.open_files(targets, 'split', ctx)
    end
  elseif kind == 'tabedit' then
    if source and type(source.on_select) == 'function' then
      M.close({ save_session = true })
      source.on_select(targets, 'tabedit', ctx)
    else
      M.close({ save_session = true })
      actions.open_files(targets, 'tabedit', ctx)
    end
  elseif kind == 'qf' then
    local qf_targets = next(state.marked) ~= nil and targets or state.items
    M.close({ save_session = true })
    actions.send_to_qf(qf_targets, ctx)
  end
end

local function choose_action()
  if not state.active or state.closing then
    return
  end
  local candidates = list_available_actions(state.source)
  if #candidates == 0 then
    vim.notify('No actions available', vim.log.levels.INFO)
    return
  end
  state.action_candidates = candidates
  state.transitioning = true

  local settled = false
  local function settle()
    if not settled then
      settled = true
      state.transitioning = false
      state.action_candidates = {}
    end
  end

  local ok, err = pcall(vim.ui.input, {
    prompt = 'Action: ',
    completion = 'customlist,v:lua.MyFinderCompleteAction',
  }, function(choice)
    settle()
    if not choice then
      return
    end
    local name = vim.trim(choice)
    if name == '' then
      return
    end
    if not vim.tbl_contains(candidates, name) then
      vim.notify('Unknown finder action: ' .. name, vim.log.levels.WARN)
      return
    end
    vim.schedule(function()
      if state.active and not state.closing then
        run_action(name, { from_chooser = true })
      end
    end)
  end)

  if not ok then
    settle()
    local msg = tostring(err)
    if not msg:find('Keyboard interrupt', 1, true) then
      vim.notify(msg, vim.log.levels.ERROR)
    end
  end
end

local function toggle_mark_normal()
  if not state.list_win or not vim.api.nvim_win_is_valid(state.list_win) then
    return
  end
  local lnum = vim.api.nvim_win_get_cursor(state.list_win)[1]
  local item = state.items[lnum]
  if not item then
    return
  end
  if state.marked[item.id] then
    state.marked[item.id] = nil
  else
    state.marked[item.id] = true
  end
  render_list(true)
  if lnum < #state.items then
    pcall(vim.api.nvim_win_set_cursor, state.list_win, { lnum + 1, 0 })
    sync_preview({})
  end
end

local function toggle_mark_visual()
  local l1 = vim.fn.line('v')
  local l2 = vim.fn.line('.')
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'nx', false)
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  for l = l1, l2 do
    local item = state.items[l]
    if item then
      if state.marked[item.id] then
        state.marked[item.id] = nil
      else
        state.marked[item.id] = true
      end
    end
  end
  render_list(true)
end

local on_filter_changed

local function setup_keymaps()
  local lbuf = state.list_buf
  local fbuf = state.filter_buf

  local function lmap(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = lbuf, nowait = true, silent = true, desc = desc })
  end

  local function fmap(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = fbuf, nowait = true, silent = true, desc = desc })
  end

  -- List Normal mode
  lmap('n', 'i', enter_filter_insert, 'Finder: enter filter')
  lmap('n', 'a', choose_action, 'Finder: choose action')
  lmap('n', '<CR>', function() run_action('open') end, 'Finder: open')
  lmap('n', 'E', function() run_action('vsplit') end, 'Finder: vsplit')
  lmap('n', 'S', function() run_action('split') end, 'Finder: split')
  lmap('n', 't', function() run_action('tabedit') end, 'Finder: tabedit')
  lmap('n', '<C-q>', function() run_action('qf') end, 'Finder: send to quickfix')
  lmap('n', ',', toggle_mark_normal, 'Finder: toggle mark')
  lmap('x', ',', toggle_mark_visual, 'Finder: toggle mark (visual)')
  lmap('n', 'c', function()
    state.marked = {}
    render_list(true)
  end, 'Finder: clear marks')
  lmap('n', 'p', toggle_preview, 'Finder: toggle preview')
  lmap('n', '<C-f>', function() preview.scroll(state.preview_win, 1) end, 'Finder: scroll preview down')
  lmap('n', '<C-b>', function() preview.scroll(state.preview_win, -1) end, 'Finder: scroll preview up')
  lmap('n', '<C-o>', '<Nop>', 'Finder: disable jumplist back')
  lmap('n', '<C-i>', '<Nop>', 'Finder: disable jumplist forward')
  lmap('n', '<C-^>', '<Nop>', 'Finder: disable alternate buffer switch')
  lmap('n', '<C-6>', '<Nop>', 'Finder: disable alternate buffer switch')
  lmap('n', 'q', function() M.close({ save_session = true, on_cancel = true }) end, 'Finder: close')
  lmap('n', '<Esc>', function() M.close({ save_session = true, on_cancel = true }) end, 'Finder: close')

  -- Source-specific extra keymaps
  if state.source and state.source.keymaps then
    for lhs, spec in pairs(state.source.keymaps) do
      local modes = type(spec.mode) == 'table' and spec.mode or { spec.mode or 'n' }
      local action_name = spec.action
      for _, mode in ipairs(modes) do
        local is_visual = mode == 'x' or mode == 'v'
        local cb = spec.fn or function()
          run_action(action_name, is_visual and { visual = true } or nil)
        end
        lmap(mode, lhs, cb, spec.desc or ('Finder: ' .. tostring(action_name or lhs)))
      end
    end
  end

  -- Filter Insert mode
  fmap('i', '<CR>', return_to_list_normal, 'Finder: finish filter')
  fmap('i', '<Esc>', return_to_list_normal, 'Finder: finish filter')
  fmap('i', 'jj', return_to_list_normal, 'Finder: finish filter')
  fmap('n', '<CR>', return_to_list_normal, 'Finder: return to list')
  fmap('n', '<Esc>', return_to_list_normal, 'Finder: return to list')
  fmap('n', '<C-o>', '<Nop>', 'Finder: disable jumplist back')
  fmap('n', '<C-i>', '<Nop>', 'Finder: disable jumplist forward')
  fmap('n', '<C-^>', '<Nop>', 'Finder: disable alternate buffer switch')
  fmap('n', '<C-6>', '<Nop>', 'Finder: disable alternate buffer switch')
  fmap('n', 'q', function() M.close({ save_session = true, on_cancel = true }) end, 'Finder: close')

  -- Readline navigation in Filter Insert mode
  fmap('i', '<C-a>', '<Home>', 'Finder filter: start of line')
  fmap('i', '<C-e>', '<End>', 'Finder filter: end of line')
  fmap('i', '<C-f>', '<Right>', 'Finder filter: forward char')
  fmap('i', '<C-b>', '<Left>', 'Finder filter: backward char')
  fmap('i', '<C-d>', '<Del>', 'Finder filter: delete char')
  fmap('i', '<C-h>', '<BS>', 'Finder filter: backspace')
  fmap('i', '<C-k>', '<C-o>D', 'Finder filter: kill to end')
  fmap('i', '<C-u>', function()
    vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, { '' })
    pcall(vim.api.nvim_win_set_cursor, state.filter_win, { 1, 0 })
    on_filter_changed()
  end, 'Finder filter: clear query')
  fmap('i', '<C-w>', '<C-w>', 'Finder filter: delete word')
  fmap('i', '<C-y>', '<C-r>*', 'Finder filter: paste')
end

on_filter_changed = function()
  if not state.active or state.closing then
    return
  end
  local raw_lines = vim.api.nvim_buf_get_lines(state.filter_buf, 0, -1, false)
  local new_query = raw_lines[1] or ''
  if #raw_lines > 1 then
    new_query = table.concat(raw_lines, ' ')
    vim.api.nvim_buf_set_lines(state.filter_buf, 0, -1, false, { new_query })
    pcall(vim.api.nvim_win_set_cursor, state.filter_win, { 1, #new_query })
  end

  if new_query == state.query then
    return
  end
  state.query = new_query
  state.ctx.query = new_query

  local debounce_ms = (state.source and state.source.debounce_ms) or 0
  if debounce_ms > 0 then
    if not state.debounce_timer then
      state.debounce_timer = uv.new_timer()
    else
      pcall(function()
        state.debounce_timer:stop()
      end)
    end
    state.debounce_timer:start(
      debounce_ms,
      0,
      vim.schedule_wrap(function()
        run_search({ preserve_cursor = false })
      end)
    )
  else
    run_search({ preserve_cursor = false })
  end
end

local function setup_autocmds()
  vim.api.nvim_clear_autocmds({ group = augroup })

  vim.api.nvim_create_autocmd({ 'TextChangedI', 'TextChanged' }, {
    group = augroup,
    buffer = state.filter_buf,
    callback = on_filter_changed,
  })

  vim.api.nvim_create_autocmd('InsertLeave', {
    group = augroup,
    buffer = state.filter_buf,
    callback = function()
      if state.active and not state.closing and not state.transitioning then
        vim.schedule(return_to_list_normal)
      end
    end,
  })

  vim.api.nvim_create_autocmd('CursorMoved', {
    group = augroup,
    buffer = state.list_buf,
    callback = function()
      if not state.active or state.closing then
        return
      end
      sync_preview({})
      if state.source and type(state.source.on_cursor_moved) == 'function'
        and state.list_win and vim.api.nvim_win_is_valid(state.list_win) then
        local lnum = vim.api.nvim_win_get_cursor(state.list_win)[1]
        state.source.on_cursor_moved(lnum, #state.items, state.ctx, state.query)
      end
    end,
  })

  vim.api.nvim_create_autocmd('WinEnter', {
    group = augroup,
    callback = function()
      if not state.active or state.closing or state.transitioning then
        return
      end
      local cur_win = vim.api.nvim_get_current_win()
      if cur_win ~= state.list_win and cur_win ~= state.filter_win and cur_win ~= state.preview_win then
        M.close({ save_session = true, on_cancel = true })
      end
    end,
  })

  vim.api.nvim_create_autocmd('VimResized', {
    group = augroup,
    callback = relayout,
  })
end

start_scan_poll_if_needed = function()
  if not state.source or not state.source.poll_scan then
    return
  end
  if not state.scanning or state.scan_poll_active then
    return
  end
  state.scan_poll_active = true
  if not state.scan_poll_timer then
    state.scan_poll_timer = uv.new_timer()
  end
  state.scan_poll_timer:start(
    60,
    60,
    vim.schedule_wrap(function()
      if not state.active or state.closing then
        stop_timers()
        return
      end
      run_search({ preserve_cursor = true, is_poll = true })
      if not state.scanning then
        state.scan_poll_active = false
        if state.scan_poll_timer then
          pcall(function()
            state.scan_poll_timer:stop()
          end)
        end
      end
    end)
  )
end

---@param source table
---@param opts? table
function M.open(source, opts)
  opts = opts or {}
  setup_highlights()

  if state.active then
    M.close({ save_session = false })
  end

  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()
  local origin_path = vim.api.nvim_buf_get_name(origin_buf)

  local show_preview
  if opts.preview_enabled ~= nil then
    show_preview = opts.preview_enabled
  elseif source.show_preview ~= nil then
    show_preview = source.show_preview
  else
    show_preview = true
  end

  state.active = true
  state.closing = false
  state.transitioning = false
  state.source = source
  state.opts = opts
  state.preview_enabled = show_preview
  state.query = opts.query or ''
  state.items = {}
  state.total_matched = 0
  state.total_items = 0
  state.scanning = false
  state.has_more = false
  state.marked = opts.marked or {}
  state.last_first_id = nil
  state.last_cursor_id = nil
  state.search_gen = 0

  state.ctx = {
    origin_win = origin_win,
    origin_buf = origin_buf,
    origin_path = origin_path,
    dir = opts.dir,
    query = state.query,
    title = source.title or 'Finder',
    track_query = source.track_query,
    on_cancel = opts.on_cancel,
    opts = opts,
  }

  if type(source.prepare) == 'function' then
    local extra = source.prepare(state.ctx, opts)
    if type(extra) == 'table' then
      for k, v in pairs(extra) do
        state.ctx[k] = v
      end
    end
  end

  bind_ctx_helpers(state.ctx)

  local layout = compute_layout(state.preview_enabled)

  local fbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[fbuf].buftype = 'nofile'
  vim.bo[fbuf].bufhidden = 'wipe'
  vim.bo[fbuf].swapfile = false
  vim.bo[fbuf].modifiable = true
  vim.b[fbuf].completion = false
  vim.api.nvim_buf_set_lines(fbuf, 0, -1, false, { state.query })

  local lbuf = vim.api.nvim_create_buf(false, true)
  vim.bo[lbuf].buftype = 'nofile'
  vim.bo[lbuf].bufhidden = 'wipe'
  vim.bo[lbuf].swapfile = false
  vim.bo[lbuf].modifiable = false
  vim.bo[lbuf].filetype = 'my-finder-list'

  state.filter_buf = fbuf
  state.list_buf = lbuf

  state.filter_win = vim.api.nvim_open_win(fbuf, false, {
    relative = 'editor',
    row = layout.filter.row,
    col = layout.filter.col,
    width = layout.filter.width,
    height = layout.filter.height,
    style = 'minimal',
    border = 'none',
    zindex = 50,
  })
  vim.wo[state.filter_win].wrap = false
  vim.wo[state.filter_win].cursorline = false
  pcall(function()
    vim.wo[state.filter_win].winfixbuf = true
  end)

  state.list_win = vim.api.nvim_open_win(lbuf, true, {
    relative = 'editor',
    row = layout.list.row,
    col = layout.list.col,
    width = layout.list.width,
    height = layout.list.height,
    style = 'minimal',
    border = 'none',
    zindex = 50,
  })
  vim.wo[state.list_win].wrap = false
  vim.wo[state.list_win].cursorline = true
  vim.wo[state.list_win].number = false
  vim.wo[state.list_win].relativenumber = false
  pcall(function()
    vim.wo[state.list_win].winfixbuf = true
  end)

  if state.preview_enabled and layout.preview then
    local pbuf = preview.ensure_buf()
    state.preview_win = vim.api.nvim_open_win(pbuf, false, {
      relative = 'editor',
      row = layout.preview.row,
      col = layout.preview.col,
      width = layout.preview.width,
      height = layout.preview.height,
      style = 'minimal',
      border = 'none',
      focusable = false,
      zindex = 50,
    })
    preview.apply_win_opts(state.preview_win)
  end

  setup_keymaps()
  setup_autocmds()

  -- Ensure we start in List window in Normal mode
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == 'i' then
    vim.cmd('stopinsert')
  end

  run_search({
    force_preview = true,
    immediate_preview = true,
    restore_cursor_id = opts.restore_cursor_id,
    restore_cursor_line = opts.restore_cursor_line,
  })
  start_scan_poll_if_needed()
end

---@return boolean
function M.is_open()
  return state.active and not state.closing
end

function M.resume()
  if not last_session or not last_session.source then
    vim.notify('No previous finder session to resume', vim.log.levels.INFO)
    return
  end
  local opts = vim.tbl_extend('force', last_session.opts or {}, {
    query = last_session.query,
    marked = vim.deepcopy(last_session.marked or {}),
    restore_cursor_id = last_session.cursor_id,
    restore_cursor_line = last_session.cursor_line,
    preview_enabled = last_session.preview_enabled,
  })
  M.open(last_session.source, opts)
end

return M
