local backend = require('my.finder.backend')

local M = {}

---@param ctx table
local function focus_origin_win(ctx)
  if ctx and ctx.origin_win and vim.api.nvim_win_is_valid(ctx.origin_win) then
    pcall(vim.api.nvim_set_current_win, ctx.origin_win)
  end
end

---@param item table
---@param cmd 'edit'|'vsplit'|'split'|'tabedit'
local function open_single(item, cmd)
  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) then
    if cmd == 'vsplit' then
      vim.cmd('vsplit')
    elseif cmd == 'split' then
      vim.cmd('split')
    elseif cmd == 'tabedit' then
      vim.cmd('tab split')
    end
    vim.api.nvim_win_set_buf(0, item.bufnr)
  elseif item.path and item.path ~= '' then
    local escaped = vim.fn.fnameescape(item.path)
    if cmd == 'edit' then
      vim.cmd('edit ' .. escaped)
    elseif cmd == 'vsplit' then
      vim.cmd('vsplit ' .. escaped)
    elseif cmd == 'split' then
      vim.cmd('split ' .. escaped)
    elseif cmd == 'tabedit' then
      vim.cmd('tabedit ' .. escaped)
    end
  end

  if item.lnum and item.lnum > 0 then
    local col = item.col or 0
    local line_count = vim.api.nvim_buf_line_count(0)
    local target_line = math.min(item.lnum, math.max(1, line_count))
    pcall(vim.api.nvim_win_set_cursor, 0, { target_line, col })
    vim.cmd('normal! zz')
  end
end

---@param items table[]
---@param cmd 'edit'|'vsplit'|'split'|'tabedit'
---@param ctx table
function M.open_files(items, cmd, ctx)
  if not items or #items == 0 then
    return
  end

  focus_origin_win(ctx)

  if #items == 1 then
    local item = items[1]
    open_single(item, cmd)
    if item.path and item.path ~= '' then
      backend.track_access(item.path)
      if ctx and ctx.track_query and ctx.dir and ctx.query and ctx.query ~= '' then
        backend.track_query(ctx.dir, ctx.query, item.path)
      end
    end
    return
  end

  if cmd == 'edit' then
    -- Load all buffers and switch current window to the first item
    for i = 2, #items do
      local it = items[i]
      if it.path and it.path ~= '' then
        local b = vim.fn.bufadd(it.path)
        vim.fn.bufload(b)
        vim.bo[b].buflisted = true
      end
    end
    open_single(items[1], 'edit')
  else
    for _, it in ipairs(items) do
      open_single(it, cmd)
    end
  end

  for _, it in ipairs(items) do
    if it.path and it.path ~= '' then
      backend.track_access(it.path)
    end
  end
  if ctx and ctx.track_query and ctx.dir and ctx.query and ctx.query ~= '' and items[1].path then
    backend.track_query(ctx.dir, ctx.query, items[1].path)
  end
end

---@param items table[]
---@param ctx table
function M.send_to_qf(items, ctx)
  if not items or #items == 0 then
    return
  end

  local qf_items = {}
  for _, it in ipairs(items) do
    if (it.path and it.path ~= '') or (it.bufnr and vim.api.nvim_buf_is_valid(it.bufnr)) then
      table.insert(qf_items, {
        filename = it.path,
        bufnr = it.bufnr,
        lnum = it.lnum or 1,
        col = (it.col or 0) + 1,
        text = it.text or it.display or '',
      })
    end
  end

  if #qf_items == 0 then
    vim.notify('No valid items for quickfix', vim.log.levels.INFO)
    return
  end

  focus_origin_win(ctx)
  vim.fn.setqflist({}, 'r', {
    title = (ctx and ctx.title) or 'Finder',
    items = qf_items,
  })
  vim.cmd('copen')
end

return M
