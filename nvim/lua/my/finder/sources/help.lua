local backend = require('my.finder.backend')

local M = {}

local uv = vim.uv or vim.loop

local cache = {
  rtp_key = nil,
  entries = nil,
  match_texts = nil,
}

local function load_help_tags()
  local rtp_key = vim.o.runtimepath .. '|' .. table.concat(vim.opt.helplang:get(), ',')
  if cache.rtp_key == rtp_key and cache.entries then
    return cache.entries, cache.match_texts
  end

  local tag_files = vim.api.nvim_get_runtime_file('doc/tags*', true)
  local entries = {}
  local match_texts = {}
  local seen = {}

  for _, tag_file in ipairs(tag_files) do
    local doc_dir = vim.fn.fnamemodify(tag_file, ':h')
    local f = io.open(tag_file, 'r')
    if f then
      for line in f:lines() do
        local tag, rel_doc, pat = line:match('^([^\t]+)\t([^\t]+)\t(.*)$')
        if tag and rel_doc and not seen[tag] then
          seen[tag] = true
          local full_doc = doc_dir .. '/' .. rel_doc
          entries[#entries + 1] = {
            id = 'help:' .. tag,
            tag = tag,
            path = full_doc,
            pattern = pat,
            display = string.format('%-36s  %s', tag, rel_doc),
            highlights = { { 38, 38 + #rel_doc, 'Comment' } },
            match_offset = 0,
          }
          match_texts[#match_texts + 1] = tag
        end
      end
      f:close()
    end
  end

  cache.rtp_key = rtp_key
  cache.entries = entries
  cache.match_texts = match_texts
  return entries, match_texts
end

---@param content string
---@param tag string
---@return string[], integer|nil, integer
local function extract_help_window(content, tag)
  local lines = vim.split(content, '\n', { plain = true })
  local needle = '*' .. tag .. '*'
  local found_lnum = nil
  for i, l in ipairs(lines) do
    if l:find(needle, 1, true) then
      found_lnum = i
      break
    end
  end

  if #lines <= 1200 or not found_lnum or found_lnum <= 800 then
    return lines, found_lnum or 1, 0
  end

  local start_l = math.max(1, found_lnum - 200)
  local end_l = math.min(#lines, found_lnum + 200)
  local sliced = {}
  for i = start_l, end_l do
    sliced[#sliced + 1] = lines[i]
  end
  return sliced, found_lnum, start_l - 1
end

function M.new()
  return {
    name = 'help',
    title = 'Help Tags',
    prompt = 'help> ',
    show_preview = true,
    allow_preview = true,

    prepare = function()
      local entries, match_texts = load_help_tags()
      return {
        entries = entries,
        match_texts = match_texts,
      }
    end,

    search = function(query, ctx)
      local res = backend.fuzzy_match_list(query, ctx.match_texts or {}, { limit = 200 })
      local items = {}
      for _, m in ipairs(res.items or {}) do
        local src = ctx.entries[m.idx]
        if src then
          items[#items + 1] = vim.tbl_extend('force', src, {
            match_indices = m.match_indices,
          })
        end
      end
      return {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_items or #ctx.entries,
        scanning = false,
      }
    end,

    preview = function(item, pctx, cb)
      if not item.path then
        cb({ '(no help file)' }, { skip_ts = true })
        return
      end
      uv.fs_open(item.path, 'r', 438, function(err, fd)
        if err or not fd then
          vim.schedule(function()
            if not pctx.is_stale() then
              cb({ '(cannot open help file)' }, { skip_ts = true })
            end
          end)
          return
        end
        uv.fs_fstat(fd, function(serr, stat)
          if serr or not stat or pctx.is_stale() then
            uv.fs_close(fd, function() end)
            return
          end
          local size = math.min(stat.size, 2 * 1024 * 1024)
          uv.fs_read(fd, size, 0, function(rerr, data)
            uv.fs_close(fd, function() end)
            if rerr or not data or pctx.is_stale() then
              return
            end
            vim.schedule(function()
              if pctx.is_stale() then
                return
              end
              local lines, lnum, offset = extract_help_window(data, item.tag)
              cb(lines, {
                path = item.path,
                lnum = lnum,
                line_offset = offset,
              })
            end)
          end)
        end)
      end)
    end,

    on_select = function(targets, cmd)
      local it = targets[1]
      if not it or not it.tag then
        return
      end
      local hcmd
      if cmd == 'vsplit' then
        hcmd = 'vertical help '
      elseif cmd == 'tabedit' then
        hcmd = 'tab help '
      else
        hcmd = 'help '
      end
      local ok, err = pcall(vim.cmd, hcmd .. it.tag)
      if not ok then
        vim.notify('help failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  }
end

return M
