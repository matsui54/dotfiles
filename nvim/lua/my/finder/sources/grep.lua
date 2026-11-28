local backend = require('my.finder.backend')

local M = {}

local function normalize_dir(dir)
  local p = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ':p')
  if #p > 1 and p:sub(-1) == '/' then
    p = p:sub(1, -2)
  end
  return p
end

---@param rel_path string
---@param count integer
---@return table
local function build_file_header(rel_path, count)
  local count_str = string.format(' (%d) ', count)
  local rule_len = math.max(4, 44 - #rel_path - #count_str)
  return {
    { '── ', 'MyFinderSectionRule' },
    { rel_path, 'MyFinderFileHeader' },
    { count_str, 'MyFinderCounter' },
    { string.rep('─', rule_len), 'MyFinderSectionRule' },
  }
end

local MODE_ORDER = { 'plain', 'regex', 'fuzzy' }
local NEXT_MODE = {
  plain = 'regex',
  regex = 'fuzzy',
  fuzzy = 'plain',
}

---@param m string|nil
---@return 'plain'|'regex'|'fuzzy'
local function normalize_mode(m)
  if m == 'regex' or m == 'fuzzy' then
    return m
  end
  return 'plain'
end

---@param mode 'plain'|'regex'|'fuzzy'
---@param has_regex_err boolean
---@return string
local function prompt_for_mode(mode, has_regex_err)
  if mode == 'regex' and has_regex_err then
    return 'grep [regex!]> '
  end
  return string.format('grep [%s]> ', mode)
end

---@param mode 'plain'|'regex'|'fuzzy'
---@return string
local function hint_for_mode(mode)
  return string.format('  Press `i` to start %s grep (<C-g> / m: switch mode)...', mode)
end

---@param ctx table
---@param mode string|nil
local function apply_mode(ctx, mode)
  local m = normalize_mode(mode)
  ctx.grep_mode = m
  ctx.prompt = prompt_for_mode(m, false)
  ctx.empty_hint = hint_for_mode(m)
  if type(ctx.opts) == 'table' then
    ctx.opts.mode = m
  end
end

---@param source_opts? table
---@return table
function M.new(source_opts)
  local initial_mode = normalize_mode(source_opts and source_opts.mode)

  local function switch_mode_action(target_mode)
    return {
      allow_empty = true,
      desc = 'Switch grep mode to ' .. target_mode,
      fn = function(_, ctx)
        apply_mode(ctx, target_mode)
        ctx.refresh({ preserve_cursor = false, force_preview = true })
        return 'keep_open'
      end,
    }
  end

  return {
    name = 'grep',
    title = 'Live Grep',
    prompt = prompt_for_mode(initial_mode, false),
    show_preview = true,
    allow_preview = true,
    poll_scan = true,
    debounce_ms = 25,
    track_query = false,
    empty_hint = hint_for_mode(initial_mode),

    prepare = function(base_ctx, opts)
      local raw_dir = (opts and opts.dir) or (source_opts and source_opts.dir) or vim.fn.getcwd()
      local target_dir = normalize_dir(raw_dir)
      local canon, err = backend.ensure_dir(target_dir)
      local mode = normalize_mode((opts and opts.mode) or initial_mode)
      if type(base_ctx.opts) == 'table' then
        base_ctx.opts.mode = mode
      end
      return {
        dir = canon or target_dir,
        dir_error = err,
        grep_mode = mode,
        prompt = prompt_for_mode(mode, false),
        empty_hint = hint_for_mode(mode),
      }
    end,

    search = function(query, ctx)
      local mode = normalize_mode(ctx.grep_mode)
      if ctx.dir_error then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      if not query or vim.trim(query) == '' then
        ctx.prompt = prompt_for_mode(mode, false)
        local st = backend.scan_status(ctx.dir)
        return {
          items = {},
          total_matched = 0,
          total_items = st.total_files or 0,
          scanning = st.scanning == true,
        }
      end

      local res = backend.live_grep(ctx.dir, query, {
        mode = mode,
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
      ctx.prompt = prompt_for_mode(mode, res.regex_fallback_error ~= nil)

      local groups = {}
      local by_path = {}
      for _, it in ipairs(res.items or {}) do
        local key = it.path or it.rel_path or ''
        local g = by_path[key]
        if not g then
          g = {
            rel_path = it.rel_path or '',
            items = {},
          }
          by_path[key] = g
          groups[#groups + 1] = g
        end
        g.items[#g.items + 1] = it
      end

      local items = {}
      for _, group in ipairs(groups) do
        local max_loc_w = 0
        for _, it in ipairs(group.items) do
          local loc_raw = string.format('%d:%d', it.lnum, (it.col or 0) + 1)
          if #loc_raw > max_loc_w then
            max_loc_w = #loc_raw
          end
        end

        for idx, it in ipairs(group.items) do
          local raw_text = it.text or ''
          local trimmed = raw_text:gsub('^%s+', '')
          local trim_len = #raw_text - #trimmed
          local loc_raw = string.format('%d:%d', it.lnum, (it.col or 0) + 1)
          local loc_str = string.format('%' .. max_loc_w .. 's  ', loc_raw)
          local display = loc_str .. trimmed

          local hls = {
            { 0, #loc_str, 'Comment' },
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

          local virt_lines_above = nil
          if idx == 1 then
            virt_lines_above = { build_file_header(group.rel_path, #group.items) }
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
            virt_lines_above = virt_lines_above,
          }
        end
      end

      return {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_files or #items,
        scanning = res.scanning == true,
      }
    end,

    keymaps = {
      ['<C-g>'] = {
        action = 'cycle_mode',
        desc = 'Finder grep: cycle mode (plain/regex/fuzzy)',
      },
      m = {
        action = 'cycle_mode',
        desc = 'Finder grep: cycle mode (plain/regex/fuzzy)',
      },
    },

    filter_keymaps = {
      ['<C-g>'] = {
        mode = { 'i', 'n' },
        action = 'cycle_mode',
        desc = 'Finder grep: cycle mode (plain/regex/fuzzy)',
      },
    },

    actions = {
      cycle_mode = {
        allow_empty = true,
        desc = 'Cycle grep mode (' .. table.concat(MODE_ORDER, ' -> ') .. ')',
        fn = function(_, ctx)
          local next_mode = NEXT_MODE[normalize_mode(ctx.grep_mode)] or 'plain'
          apply_mode(ctx, next_mode)
          ctx.refresh({ preserve_cursor = false, force_preview = true })
          return 'keep_open'
        end,
      },
      mode_plain = switch_mode_action('plain'),
      mode_regex = switch_mode_action('regex'),
      mode_fuzzy = switch_mode_action('fuzzy'),
    },
  }
end

return M
