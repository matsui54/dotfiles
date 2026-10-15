return {
  -- itchyny/lightline.vim
  {
    'itchyny/lightline.vim',
    lazy = false,
    dependencies = {
      'itchyny/vim-gitbranch',
    },
    init = function()
      vim.g.lightline = {
        colorscheme = 'shirotelin',
        active = {
          left = {
            { 'mode', 'paste' },
            { 'readonly' },
            { 'gitbranch', 'relativepath', 'modified' },
          },
        },
        enable = {
          statusline = 1,
          tabline = 0,
        },
        subseparator = {
          left = '|',
          right = '|',
        },
        component = {
          lineinfo = '%3l/%L:%-2c',
        },
        component_function = {
          gitbranch = 'gitbranch#name',
        },
      }
    end,
  },
}
