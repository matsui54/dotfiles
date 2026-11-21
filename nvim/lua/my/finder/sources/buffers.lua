local backend = require('my.finder.backend')

local M = {}

local function collect_buffers(origin_buf)
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  local alt_buf = vim.fn.bufnr('#')

  table.sort(infos, function(a, b)
    if a.bufnr == origin_buf and b.bufnr ~= origin_buf then
      return false
    end
    if b.bufnr == origin_buf and a.bufnr ~= origin_buf then
      return true
    end
    if a.bufnr == alt_buf and b.bufnr ~= alt_buf then
      return true
    end
    if b.bufnr == alt_buf and a.bufnr ~= alt_buf then
      return false
    end
    return (a.lastused or 0) > (b.lastused or 0)
  end)

  local cwd = vim.fs.normalize(vim.fn.getcwd())
  local entries = {}
  local match_texts = {}

  for _, b in ipairs(infos) do
    local name = b.name or ''
    local label
    if name == '' then
      label = '[No Name]'
    else
      local norm = vim.fs.normalize(name)
      if norm:sub(1, #cwd + 1) == cwd .. '/' then
        label = norm:sub(#cwd + 2)
      else
        label = vim.fn.fnamemodify(name, ':~')
      end
    end

    local cur_mark = (b.bufnr == origin_buf and '%') or (b.bufnr == alt_buf and '#') or ' '
    local mod_mark = (b.changed == 1) and '+' or ' '
    local prefix = string.format('%3d %s%s ', b.bufnr, cur_mark, mod_mark)

    local hls = {
      { 0, 3, 'Number' },
    }
    if mod_mark == '+' then
      table.insert(hls, { 5, 6, 'DiagnosticWarn' })
    end

    entries[#entries + 1] = {
      id = 'buf:' .. tostring(b.bufnr),
      bufnr = b.bufnr,
      path = name ~= '' and name or nil,
      lnum = b.lnum and b.lnum > 0 and b.lnum or nil,
      display = prefix .. label,
      highlights = hls,
      match_offset = #prefix,
    }
    match_texts[#match_texts + 1] = label
  end

  return entries, match_texts
end

function M.new()
  return {
    name = 'buffers',
    title = 'Buffers',
    prompt = 'buf> ',
    show_preview = true,
    allow_preview = true,

    prepare = function(ctx)
      local entries, match_texts = collect_buffers(ctx.origin_buf)
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

    keymaps = {
      d = {
        action = 'delete_buf',
        desc = 'Finder buffers: delete buffer',
      },
    },

    actions = {
      delete_buf = function(targets, ctx)
        for _, it in ipairs(targets) do
          if it.bufnr and vim.api.nvim_buf_is_valid(it.bufnr) then
            pcall(vim.api.nvim_buf_delete, it.bufnr, { force = false })
          end
        end
        local entries, match_texts = collect_buffers(ctx.origin_buf)
        ctx.entries = entries
        ctx.match_texts = match_texts
        ctx.refresh(true)
        return 'keep_open'
      end,
    },
  }
end

return M
