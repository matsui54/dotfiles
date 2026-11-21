local backend = require('my.finder.backend')

local M = {}

local uv = vim.uv or vim.loop

function M.new()
  return {
    name = 'oldfiles',
    title = 'Oldfiles',
    prompt = 'old> ',
    show_preview = true,
    allow_preview = true,

    prepare = function()
      local cwd = vim.fs.normalize(vim.fn.getcwd())
      local seen = {}
      local entries = {}
      local match_texts = {}

      for _, raw in ipairs(vim.v.oldfiles or {}) do
        if type(raw) == 'string' and raw ~= '' and not raw:match('^term://') then
          local norm = vim.fs.normalize(raw)
          if not seen[norm] then
            seen[norm] = true
            local st = uv.fs_stat(norm)
            if st and st.type ~= 'directory' then
              local label
              if norm:sub(1, #cwd + 1) == cwd .. '/' then
                label = norm:sub(#cwd + 2)
              else
                label = vim.fn.fnamemodify(norm, ':~')
              end
              entries[#entries + 1] = {
                id = norm,
                path = norm,
                display = label,
                match_offset = 0,
              }
              match_texts[#match_texts + 1] = label
            end
          end
        end
      end

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
  }
end

return M
