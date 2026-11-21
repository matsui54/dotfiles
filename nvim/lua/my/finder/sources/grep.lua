local backend = require('my.finder.backend')

local M = {}

local function normalize_dir(dir)
  local p = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ':p')
  if #p > 1 and p:sub(-1) == '/' then
    p = p:sub(1, -2)
  end
  return p
end

function M.new()
  return {
    name = 'grep',
    title = 'Live Grep (plain)',
    prompt = 'grep> ',
    show_preview = true,
    allow_preview = true,
    poll_scan = true,
    debounce_ms = 25,
    track_query = false,
    empty_hint = '  Press `i` to start plain grep...',

    prepare = function(_, opts)
      local raw_dir = (opts and opts.dir) or vim.fn.getcwd()
      local target_dir = normalize_dir(raw_dir)
      local canon, err = backend.ensure_dir(target_dir)
      return {
        dir = canon or target_dir,
        dir_error = err,
      }
    end,

    search = function(query, ctx)
      if ctx.dir_error then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      if not query or vim.trim(query) == '' then
        local st = backend.scan_status(ctx.dir)
        return {
          items = {},
          total_matched = 0,
          total_items = st.total_files or 0,
          scanning = st.scanning == true,
        }
      end

      local res = backend.live_grep(ctx.dir, query, {
        limit = 200,
        max_matches_per_file = 30,
      })
      if not res then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      local items = {}
      for _, it in ipairs(res.items or {}) do
        local raw_text = it.text or ''
        local trimmed = raw_text:gsub('^%s+', '')
        local trim_len = #raw_text - #trimmed
        local loc_str = string.format('%s:%d:%d: ', it.rel_path, it.lnum, (it.col or 0) + 1)
        local display = loc_str .. trimmed

        local hls = {
          { 0, #it.rel_path, 'Identifier' },
          { #it.rel_path, #loc_str, 'Comment' },
        }

        if it.match_ranges then
          for _, r in ipairs(it.match_ranges) do
            local s = #loc_str + math.max(0, (r[1] or 0) - trim_len)
            local e = #loc_str + math.max(0, (r[2] or 0) - trim_len)
            if e > s and e <= #display then
              table.insert(hls, { s, e, 'MyFinderMatch' })
            end
          end
        end

        items[#items + 1] = {
          id = string.format('%s:%d:%d', it.path, it.lnum, it.col or 0),
          path = it.path,
          rel_path = it.rel_path,
          lnum = it.lnum,
          col = it.col or 0,
          text = raw_text,
          match_ranges = it.match_ranges,
          display = display,
          highlights = hls,
        }
      end

      return {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_files or #items,
        scanning = res.scanning == true,
      }
    end,
  }
end

return M
