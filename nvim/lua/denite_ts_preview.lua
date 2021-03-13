local pfiletype = require('plenary.filetype')

local has_ts, _ = pcall(require, 'nvim-treesitter')
local _, ts_highlight = pcall(require, 'nvim-treesitter.highlight')
local _, ts_parsers = pcall(require, 'nvim-treesitter.parsers')

local previewed_buffer = 0
local previewing_job = 0

local M = {}

local read_file_async = function(filepath, callback)
  vim.loop.fs_open(filepath, "r", 438, function(err_open, fd)
    if err_open then
      print("We tried to open this file but couldn't. We failed with following error message: " .. err_open)
      return
    end
    vim.loop.fs_fstat(fd, function(err_fstat, stat)
      assert(not err_fstat, err_fstat)
      if stat.type ~= 'file' then return callback('') end
      vim.loop.fs_read(fd, stat.size, 0, function(err_read, data)
        assert(not err_read, err_read)
        vim.loop.fs_close(fd, function(err_close)
          assert(not err_close, err_close)
          return callback(data)
        end)
      end)
    end)
  end)
end

local function has_filetype(ft)
    return ft and ft ~= ''
end

--- Attach regex highlighter
local regex_highlighter = function(bufnr, ft)
  if has_filetype(ft) then
    vim.api.nvim_buf_set_option(bufnr, "syntax", ft)
    return true
  end
  return false
end

-- Attach ts highlighter
local ts_highlighter = function(bufnr, ft)
  if not has_ts then
    has_ts, _ = pcall(require, 'nvim-treesitter')
    if has_ts then
      _, ts_highlight = pcall(require, 'nvim-treesitter.highlight')
      _, ts_parsers = pcall(require, 'nvim-treesitter.parsers')
    end
  end

  if has_ts and has_filetype(ft) then
    local lang = ts_parsers.ft_to_lang(ft);
    if ts_parsers.has_parser(lang) then
      ts_highlight.attach(bufnr, lang)
      return true
    end
  end
  return false
end

--- Attach default highlighter which will choose between regex and ts
local highlighter = function(bufnr, ft)
  -- if not(ts_highlighter(bufnr, ft)) then
  --   regex_highlighter(bufnr, ft)
  -- end
  ts_highlighter(bufnr, ft)
end

local previewer = function(filepath, bufnr)
  local ft = pfiletype.detect(filepath)

  if not vim.in_fast_event() then filepath = vim.fn.expand(filepath) end
  read_file_async(filepath, vim.schedule_wrap(function(data)
    if not vim.api.nvim_buf_is_valid(bufnr) then return end
    local ok = pcall(vim.api.nvim_buf_set_lines, bufnr, 0, -1, false, vim.split(data, '[\r]?\n'))
    if not ok then return end

    highlighter(bufnr, ft)
  end))
end

local make_context = function(context)
  local new_context = {}
  new_context.preview_width = context.preview_width
  new_context.preview_height = context.preview_height
  new_context.vertical_preview = context.vertical_preview
  new_context.floating_preview = context.floating_preview
  new_context.split = context.split
  new_context.winrow = context.winrow
  new_context.wincol = context.wincol
  return new_context
end

function M.show(context)
  local target = context['targets'][1]

  if previewed_buffer == 0 or vim.tbl_isempty(vim.fn.win_findbuf(previewed_buffer)) then
    local prev_id = vim.fn.win_getid()
    vim.fn['denite#helper#preview_file'](make_context(context), '')
    vim.bo.buftype = 'nofile'
    local bufnr = vim.fn.bufnr('%')
    previewed_buffer = bufnr
    vim.g['denite#_previewing_bufnr'] = bufnr
    vim.fn.win_gotoid(prev_id)
  end

  -- vim.loop.loop_close()
  -- if previewing_job ~= 0 then
  --   print(previewing_job)
  --   vim.loop.cancel(previewing_job)
  -- end

  local path = ''
  local action_bufnr = target['action__bufnr']
  if action_bufnr then
    path = vim.fn.bufname(action_bufnr)
  else
    path = target['action__path']
  end

  previewer(path, previewed_buffer)
end

return M
