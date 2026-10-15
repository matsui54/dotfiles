return {
  -- machakann/vim-swap
  {
    'machakann/vim-swap',
    keys = {
      { '<leader>gs', '<Plug>(swap-interactive)', mode = { 'n', 'x' }, desc = 'Swap: Interactive' },
      { 'g<', '<Plug>(swap-prev)', mode = 'n', desc = 'Swap: Prev' },
      { 'g>', '<Plug>(swap-next)', mode = 'n', desc = 'Swap: Next' },
    },
    init = function()
      vim.g.swap_no_default_key_mappings = 1
    end,
  },

  -- cohama/lexima.vim
  {
    'cohama/lexima.vim',
    event = 'InsertEnter',
    init = function()
      vim.g.lexima_ctrlh_as_backspace = 1
    end,
    config = function()
      vim.fn['lexima#add_rule']({ char = "'", input = "'", filetype = { 'verilog', 'systemverilog' } })
      vim.fn['lexima#add_rule']({ char = '`', input = '`', filetype = { 'verilog', 'systemverilog' } })
    end,
  },
  -- machakann/vim-sandwich
  {
    'machakann/vim-sandwich',
    lazy = false,
    init = function()
      vim.keymap.set({ 'n', 'x' }, 's', '<Nop>')
    end,
  },

  -- sgur/vim-textobj-parameter
  {
    'sgur/vim-textobj-parameter',
    lazy = false,
    dependencies = {
      'kana/vim-textobj-user',
    },
  },
}
