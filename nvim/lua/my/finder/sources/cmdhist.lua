local backend = require('my.finder.backend')

local M = {}

function M.new()
  return {
    name = 'cmdhist',
    title = 'Command History',
    prompt = ': ',
    show_preview = false,
    allow_preview = false,

    prepare = function()
      local total = vim.fn.histnr('cmd')
      local seen = {}
      local entries = {}
      local match_texts = {}

      for i = total, 1, -1 do
        local cmd = vim.fn.histget('cmd', i)
        if type(cmd) == 'string' and cmd ~= '' and not seen[cmd] then
          seen[cmd] = true
          entries[#entries + 1] = {
            id = 'cmd:' .. tostring(#entries + 1),
            cmd = cmd,
            display = cmd,
            match_offset = 0,
          }
          match_texts[#match_texts + 1] = cmd
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

    keymaps = {
      ['<C-r>'] = {
        action = 'exec_now',
        desc = 'Finder cmdhist: execute immediately',
      },
    },

    actions = {
      exec_now = function(targets, ctx)
        local it = targets[1]
        ctx.close()
        if it and it.cmd then
          vim.schedule(function()
            local ok, err = pcall(vim.cmd, it.cmd)
            if not ok then
              vim.notify(tostring(err), vim.log.levels.ERROR)
            end
          end)
        end
      end,
    },

    on_select = function(targets)
      local it = targets[1]
      if not it or not it.cmd then
        return
      end
      vim.schedule(function()
        local keys = vim.api.nvim_replace_termcodes(':' .. it.cmd, true, false, true)
        vim.api.nvim_feedkeys(keys, 'n', false)
      end)
    end,
  }
end

return M
