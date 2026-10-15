return {
  -- Shougo/deol.nvim
  {
    'Shougo/deol.nvim',
    cmd = 'Deol',
    keys = {
      {
        [[<C-\><C-\>]],
        function()
          local split = (vim.fn.winnr('$') == 1 and vim.fn.bufname() == '') and '' or 'vertical'
          vim.fn['deol#start']({
            ['no-auto-cd'] = true,
            toggle = true,
            winwidth = math.floor(vim.o.columns / 2),
            split = split,
          })
        end,
        mode = 'n',
        desc = 'Deol: Toggle vertical terminal',
      },
      {
        [[<C-\><C-\>]],
        [[<C-\><C-N><cmd>call deol#start(#{ no-auto-cd: v:true, toggle: v:true })<CR>]],
        mode = 't',
        desc = 'Deol: Toggle terminal in terminal mode',
      },
      {
        [[<C-\>j]],
        function()
          vim.fn['deol#start']({
            ['no-auto-cd'] = true,
            toggle = true,
            split = 'h',
          })
        end,
        mode = 'n',
        desc = 'Deol: Toggle horizontal terminal',
      },
    },
  },
}
