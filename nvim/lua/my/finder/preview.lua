local uv = vim.uv or vim.loop

local M = {}

local ns = vim.api.nvim_create_namespace('my_finder_preview')

local PREVIEW_MAX_FILE_SIZE = 10 * 1024 * 1024 -- 10MB hard ceiling for full read
local CHUNK_SIZE = 65536                       -- 64KB async read chunk
local BINARY_SNIFF_BYTES = 4096
local DEBOUNCE_MS = 20
local MAX_TS_LINES = 5000
local MAX_TS_LINE_BYTES = 2000
local MAX_PREVIEW_LINES = 1500
local WINDOW_MARGIN_LINES = 300

local state = {
  buf = nil,
  gen = 0,
  last_id = nil,
  timer = nil,
}

---@return integer
function M.ensure_buf()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    return state.buf
  end
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].bufhidden = 'hide'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].undolevels = -1
  state.buf = buf
  return buf
end

---@param win integer
function M.apply_win_opts(win)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  vim.wo[win].wrap = false
  vim.wo[win].number = true
  vim.wo[win].relativenumber = false
  vim.wo[win].cursorline = false
  vim.wo[win].signcolumn = 'no'
  vim.wo[win].foldenable = false
  vim.wo[win].list = false
  pcall(function()
    vim.wo[win].winfixbuf = true
  end)
end

function M.reset()
  state.gen = state.gen + 1
  state.last_id = nil
  if state.timer then
    pcall(function()
      state.timer:stop()
    end)
  end
end

function M.dispose()
  M.reset()
  if state.timer then
    pcall(function()
      if not state.timer:is_closing() then
        state.timer:close()
      end
    end)
    state.timer = nil
  end
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
  end
  state.buf = nil
end

---@param buf integer
---@param path string|nil
---@param lines string[]
local function attach_lightweight_ts(buf, path, lines)
  pcall(vim.treesitter.stop, buf)
  if not path or path == '' or #lines == 0 or #lines > MAX_TS_LINES then
    return
  end

  local check_n = math.min(#lines, 50)
  for i = 1, check_n do
    if #lines[i] > MAX_TS_LINE_BYTES then
      return
    end
  end

  local ft = vim.filetype.match({ filename = path, buf = buf })
  if not ft or ft == '' then
    return
  end

  local lang = vim.treesitter.language.get_lang(ft) or ft
  if not lang or lang == '' then
    return
  end

  pcall(vim.treesitter.start, buf, lang)
end

---@param win integer
---@param lines string[]
---@param opts? { path?: string, lnum?: integer, col?: integer, line_offset?: integer, ranges?: integer[][], skip_ts?: boolean }
local function render_lines(win, lines, opts)
  opts = opts or {}
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = M.ensure_buf()
  if vim.api.nvim_win_get_buf(win) ~= buf then
    pcall(function()
      vim.wo[win].winfixbuf = false
    end)
    vim.api.nvim_win_set_buf(win, buf)
  end
  M.apply_win_opts(win)

  pcall(vim.treesitter.stop, buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false
  vim.bo[buf].modified = false

  if not opts.skip_ts then
    attach_lightweight_ts(buf, opts.path, lines)
  end

  local line_offset = opts.line_offset or 0
  local target_lnum = opts.lnum
  if target_lnum and target_lnum > 0 and #lines > 0 then
    local display_lnum = math.max(1, math.min(target_lnum - line_offset, #lines))
    local lnum_0 = display_lnum - 1
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum_0, 0, {
      line_hl_group = 'CursorLine',
    })

    if opts.ranges then
      local line_len = #lines[display_lnum]
      for _, r in ipairs(opts.ranges) do
        local s_col = math.max(0, math.min(r[1] or 0, line_len))
        local e_col = math.max(s_col, math.min(r[2] or s_col, line_len))
        if e_col > s_col then
          pcall(vim.api.nvim_buf_set_extmark, buf, ns, lnum_0, s_col, {
            end_col = e_col,
            hl_group = 'Search',
            priority = 200,
          })
        end
      end
    end

    local col = math.min(opts.col or 0, #lines[display_lnum])
    pcall(vim.api.nvim_win_call, win, function()
      pcall(vim.api.nvim_win_set_cursor, win, { display_lnum, col })
      vim.cmd('normal! zz')
    end)
  else
    pcall(vim.api.nvim_win_call, win, function()
      pcall(vim.api.nvim_win_set_cursor, win, { 1, 0 })
      vim.cmd('normal! zt')
    end)
  end
end

---@param win integer
---@param text string
local function render_message(win, text)
  render_lines(win, { text }, { skip_ts = true })
  local buf = M.ensure_buf()
  pcall(vim.api.nvim_buf_set_extmark, buf, ns, 0, 0, {
    end_col = #text,
    hl_group = 'Comment',
  })
end

---@param raw string
---@param target_lnum integer|nil
---@return string[], integer
local function split_windowed_lines(raw, target_lnum)
  local all = vim.split(raw, '\n', { plain = true })
  if #all > 1 and all[#all] == '' then
    table.remove(all, #all)
  end

  if #all <= MAX_PREVIEW_LINES then
    return all, 0
  end

  local center = target_lnum or 1
  if center <= MAX_PREVIEW_LINES - 100 then
    local sliced = {}
    for i = 1, MAX_PREVIEW_LINES do
      sliced[i] = all[i]
    end
    return sliced, 0
  end

  local start_l = math.max(1, center - WINDOW_MARGIN_LINES)
  local end_l = math.min(#all, center + WINDOW_MARGIN_LINES)
  local sliced = {}
  for i = start_l, end_l do
    sliced[#sliced + 1] = all[i]
  end
  return sliced, start_l - 1
end

---@param win integer
---@param buf integer
---@param item table
local function preview_loaded_buffer(win, buf, item)
  local total = vim.api.nvim_buf_line_count(buf)
  local target_lnum = item.lnum or 1
  local start_0 = 0
  local end_0 = math.min(total, MAX_PREVIEW_LINES)

  if total > MAX_PREVIEW_LINES and target_lnum > MAX_PREVIEW_LINES - 100 then
    start_0 = math.max(0, target_lnum - WINDOW_MARGIN_LINES - 1)
    end_0 = math.min(total, target_lnum + WINDOW_MARGIN_LINES)
  end

  local lines = vim.api.nvim_buf_get_lines(buf, start_0, end_0, false)
  render_lines(win, lines, {
    path = item.path or vim.api.nvim_buf_get_name(buf),
    lnum = item.lnum,
    col = item.col,
    line_offset = start_0,
    ranges = item.match_ranges,
  })
end

---@param win integer
---@param item table
---@param gen integer
local function preview_file_async(win, item, gen)
  local path = item.path
  if not path or path == '' then
    render_message(win, '(no preview)')
    return
  end

  local target_lnum = item.lnum

  uv.fs_open(path, 'r', 438, function(open_err, fd)
    if open_err or not fd then
      vim.schedule(function()
        if gen == state.gen and vim.api.nvim_win_is_valid(win) then
          render_message(win, '[Cannot open file: ' .. tostring(open_err) .. ']')
        end
      end)
      return
    end

    local closed = false
    local function close_fd()
      if not closed then
        closed = true
        uv.fs_close(fd, function() end)
      end
    end

    if gen ~= state.gen then
      close_fd()
      return
    end

    uv.fs_fstat(fd, function(stat_err, stat)
      if stat_err or not stat or gen ~= state.gen then
        close_fd()
        return
      end

      if stat.type == 'directory' then
        close_fd()
        vim.schedule(function()
          if gen == state.gen and vim.api.nvim_win_is_valid(win) then
            render_message(win, '[Directory: ' .. path .. ']')
          end
        end)
        return
      end

      if stat.size == 0 then
        close_fd()
        vim.schedule(function()
          if gen == state.gen and vim.api.nvim_win_is_valid(win) then
            render_message(win, '[Empty file]')
          end
        end)
        return
      end

      -- If no specific deep line target, only read up to 256KB for instant preview.
      -- For deep grep/LSP line targets inside <=10MB files, allow reading up to file size.
      local read_limit
      if stat.size > PREVIEW_MAX_FILE_SIZE then
        read_limit = 256 * 1024
      elseif target_lnum and target_lnum > 500 then
        read_limit = stat.size
      else
        read_limit = math.min(stat.size, 256 * 1024)
      end

      local chunks = {}
      local bytes_read = 0
      local first_chunk = true

      local function read_next()
        if gen ~= state.gen then
          close_fd()
          return
        end
        local to_read = math.min(CHUNK_SIZE, read_limit - bytes_read)
        if to_read <= 0 then
          close_fd()
          local content = table.concat(chunks)
          vim.schedule(function()
            if gen ~= state.gen or not vim.api.nvim_win_is_valid(win) then
              return
            end
            if stat.size > PREVIEW_MAX_FILE_SIZE and target_lnum and target_lnum > 2000 then
              render_message(
                win,
                string.format('[File too large for deep line preview (%d MB)]', math.floor(stat.size / (1024 * 1024)))
              )
              return
            end
            local lines, offset = split_windowed_lines(content, target_lnum)
            if stat.size > read_limit and offset == 0 then
              table.insert(lines, string.format('... [truncated, total %d bytes] ...', stat.size))
            end
            render_lines(win, lines, {
              path = path,
              lnum = target_lnum,
              col = item.col,
              line_offset = offset,
              ranges = item.match_ranges,
            })
          end)
          return
        end

        uv.fs_read(fd, to_read, bytes_read, function(read_err, data)
          if read_err or gen ~= state.gen then
            close_fd()
            return
          end
          if not data or #data == 0 then
            read_limit = bytes_read
            read_next()
            return
          end

          if first_chunk then
            first_chunk = false
            local sniff = data:sub(1, BINARY_SNIFF_BYTES)
            if sniff:find('\0', 1, true) then
              close_fd()
              vim.schedule(function()
                if gen == state.gen and vim.api.nvim_win_is_valid(win) then
                  render_message(win, string.format('[Binary file: %d bytes]', stat.size))
                end
              end)
              return
            end
          end

          bytes_read = bytes_read + #data
          chunks[#chunks + 1] = data
          read_next()
        end)
      end

      read_next()
    end)
  end)
end

---@param win integer
---@param item table|nil
---@param source table|nil
---@param gen integer
local function run_preview(win, item, source, gen)
  if gen ~= state.gen or not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  if not item then
    render_message(win, '')
    return
  end

  -- 1. Custom async source preview hook
  if source and type(source.preview) == 'function' then
    local function apply_preview(lines, ropts)
      if gen ~= state.gen or not vim.api.nvim_win_is_valid(win) then
        return
      end
      if type(lines) == 'table' then
        render_lines(win, lines, ropts)
      else
        render_message(win, tostring(lines or ''))
      end
    end

    source.preview(item, {
      win = win,
      gen = gen,
      is_stale = function()
        if gen ~= state.gen then
          return true
        end
        if vim.in_fast_event() then
          return false
        end
        return not vim.api.nvim_win_is_valid(win)
      end,
    }, function(lines, ropts)
      if vim.in_fast_event() then
        vim.schedule(function()
          apply_preview(lines, ropts)
        end)
      else
        apply_preview(lines, ropts)
      end
    end)
    return
  end

  -- 2. Inline static preview lines
  if type(item.preview_lines) == 'table' then
    render_lines(win, item.preview_lines, {
      path = item.path,
      lnum = item.lnum,
      col = item.col,
      ranges = item.match_ranges,
      skip_ts = item.skip_ts,
    })
    return
  end

  -- 3. In-memory loaded buffer fast-path
  local loaded_buf = nil
  if item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr) and vim.api.nvim_buf_is_loaded(item.bufnr) then
    loaded_buf = item.bufnr
  elseif item.path and item.path ~= '' and vim.fn.bufloaded(item.path) == 1 then
    local b = vim.fn.bufnr(item.path)
    if b ~= -1 and vim.api.nvim_buf_is_loaded(b) then
      loaded_buf = b
    end
  end

  if loaded_buf then
    preview_loaded_buffer(win, loaded_buf, item)
    return
  end

  -- 4. Async uv.fs_* file reader
  preview_file_async(win, item, gen)
end

---@param win integer|nil
---@param item table|nil
---@param source table|nil
---@param opts? { force?: boolean, immediate?: boolean }
function M.schedule(win, item, source, opts)
  opts = opts or {}
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end

  local item_id = item and (item.preview_id or item.id or item.path or item.display) or '__EMPTY__'
  if not opts.force and item_id == state.last_id then
    return
  end

  state.last_id = item_id
  state.gen = state.gen + 1
  local gen = state.gen

  if state.timer then
    pcall(function()
      state.timer:stop()
    end)
  end

  if opts.immediate then
    run_preview(win, item, source, gen)
    return
  end

  if not state.timer then
    state.timer = uv.new_timer()
  end

  state.timer:start(
    DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      run_preview(win, item, source, gen)
    end)
  )
end

---@param win integer|nil
---@param direction 1|-1
function M.scroll(win, direction)
  if not win or not vim.api.nvim_win_is_valid(win) then
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if line_count == 0 then
    return
  end

  local height = vim.api.nvim_win_get_height(win)
  local step = math.max(1, math.floor(height / 2))

  vim.api.nvim_win_call(win, function()
    local view = vim.fn.winsaveview()
    local max_top = math.max(1, line_count - height + 1)
    local new_top = math.max(1, math.min(max_top, view.topline + (direction * step)))
    view.topline = new_top
    view.lnum = math.max(1, math.min(line_count, new_top + math.floor(height / 2)))
    vim.fn.winrestview(view)
  end)
end

return M
