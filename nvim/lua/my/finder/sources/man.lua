local backend = require('my.finder.backend')

local M = {}

local cache = {
  entries = nil,
  match_texts = nil,
}

---@param raw string
---@return table[], string[]
local function parse_man_k(raw)
  local entries = {}
  local match_texts = {}
  local seen = {}

  for _, line in ipairs(vim.split(raw, '\n', { plain = true, trimempty = true })) do
    local name_part, sec, desc = line:match('^(.-)%s*%(([^)%s]+)%)%s*%-%s*(.*)$')
    if name_part and sec then
      local first_name = vim.trim(name_part:match('^([^,]+)') or name_part)
      local ref = string.format('%s(%s)', first_name, sec)
      if first_name ~= '' and not seen[ref] then
        seen[ref] = true
        local display = string.format('%-32s  %s', ref, desc or '')
        entries[#entries + 1] = {
          id = 'man:' .. ref,
          name = first_name,
          section = sec,
          ref = ref,
          display = display,
          highlights = { { 34, #display, 'Comment' } },
          match_offset = 0,
        }
        match_texts[#match_texts + 1] = display
      end
    end
  end

  return entries, match_texts
end

function M.new()
  return {
    name = 'man',
    title = 'Man Pages',
    prompt = 'man> ',
    show_preview = true,
    allow_preview = true,
    builtin_actions = { 'open', 'vsplit', 'split', 'tabedit' },

    prepare = function()
      return {
        entries = cache.entries,
        match_texts = cache.match_texts,
      }
    end,

    search = function(query, ctx, async_cb)
      local function build_response()
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
      end

      if ctx.entries then
        return build_response()
      end

      vim.system({ 'man', '-k', '.' }, { text = true }, function(res)
        vim.schedule(function()
          if res.code == 0 and res.stdout then
            cache.entries, cache.match_texts = parse_man_k(res.stdout)
          else
            cache.entries, cache.match_texts = {}, {}
          end
          ctx.entries = cache.entries
          ctx.match_texts = cache.match_texts
          async_cb(build_response())
        end)
      end)

      return {
        items = {},
        total_matched = 0,
        total_items = 0,
        scanning = true,
      }
    end,

    preview = function(item, pctx, cb)
      if not item.name or not item.section then
        cb({ '(no man page)' }, { skip_ts = true })
        return
      end
      local width = tostring(math.max(40, vim.api.nvim_win_get_width(pctx.win) - 4))
      vim.system(
        { 'man', item.section, item.name },
        {
          text = true,
          env = {
            MANWIDTH = width,
            MANPAGER = 'cat',
            PAGER = 'cat',
            LANG = 'C.UTF-8',
          },
        },
        function(res)
          vim.schedule(function()
            if pctx.is_stale() then
              return
            end
            if res.code ~= 0 or not res.stdout then
              cb({ 'man failed: ' .. tostring(res.stderr or '') }, { skip_ts = true })
              return
            end
            local clean = res.stdout:gsub('.\b', '')
            local lines = vim.split(clean, '\n', { plain = true })
            if #lines > 1000 then
              local trimmed = {}
              for i = 1, 1000 do
                trimmed[i] = lines[i]
              end
              lines = trimmed
            end
            cb(lines, { skip_ts = true })
          end)
        end
      )
    end,

    on_select = function(targets, cmd)
      local it = targets[1]
      if not it or not it.ref then
        return
      end
      pcall(vim.cmd, 'runtime ftplugin/man.vim')
      local mcmd
      if cmd == 'vsplit' then
        mcmd = 'vertical Man '
      elseif cmd == 'tabedit' then
        mcmd = 'tab Man '
      else
        mcmd = 'Man '
      end
      local ok, err = pcall(vim.cmd, mcmd .. vim.fn.fnameescape(it.ref))
      if not ok then
        vim.notify('Man failed: ' .. tostring(err), vim.log.levels.ERROR)
      end
    end,
  }
end

return M
