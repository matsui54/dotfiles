return {
  {
    'nvim-treesitter/nvim-treesitter',
    lazy = false,
    build = ':TSUpdate',
    config = function()
      -- Install parsers
      require('nvim-treesitter').install({
        'c',
        'javascript',
        'rust',
        'python',
        'toml',
        'typescript',
        'systemverilog',
      })

      -- Enable highlight
      vim.api.nvim_create_autocmd('FileType', {
        pattern = {
          'c',
          'python',
          'rust',
          'typescript',
          'vim',
          'toml',
          'systemverilog',
        },
        callback = function()
          vim.treesitter.start()
        end,
      })
    end,
  },
}
