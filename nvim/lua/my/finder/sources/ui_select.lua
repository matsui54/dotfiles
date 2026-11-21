local backend = require('my.finder.backend')

local M = {}

---@param raw_items any[]
---@param opts? table
---@param on_choice fun(item: any, idx: integer|nil)
---@return table
function M.new(raw_items, opts, on_choice)
  opts = opts or {}
  local format_item = opts.format_item or tostring
  local prompt = opts.prompt and (vim.trim(opts.prompt) .. ' ') or 'select> '

  local called = false
  local function finish(selected, idx)
    if called then
      return
    end
    called = true
    vim.schedule(function()
      on_choice(selected, idx)
    end)
  end

  local entries = {}
  local match_texts = {}
  for i, item in ipairs(raw_items or {}) do
    local text = tostring(format_item(item)):gsub('[\r\n]+', ' ')
    entries[#entries + 1] = {
      id = 'select:' .. tostring(i),
      raw = item,
      raw_idx = i,
      display = text,
      match_offset = 0,
    }
    match_texts[#match_texts + 1] = text
  end

  return {
    name = 'ui_select',
    title = opts.prompt or 'Select',
    prompt = prompt,
    show_preview = false,
    allow_preview = false,
    no_resume = true,

    prepare = function(ctx)
      ctx.on_cancel = function()
        finish(nil, nil)
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

    on_select = function(targets)
      local it = targets[1]
      if it then
        finish(it.raw, it.raw_idx)
      else
        finish(nil, nil)
      end
    end,
  }
end

return M
