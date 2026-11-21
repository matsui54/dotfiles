vim.api.nvim_create_autocmd('User', {
  group = vim.api.nvim_create_augroup('my.finder_init', { clear = true }),
  pattern = 'VeryLazy',
  once = true,
  callback = function()
    local finder = require('my.finder')
    finder.init({ quiet = true })
    finder.register_ui_select()
  end,
})

-- コマンドライン入力中の <C-t> で command_history を起動
vim.keymap.set('c', '<C-t>', function()
  local cmdline = vim.fn.getcmdline()
  vim.schedule(function()
    require('my.finder').command_history({ query = cmdline })
  end)
  return '<C-u><Esc>'
end, { expr = true, silent = true, desc = 'Finder: Command history' })

vim.keymap.set('n', '<Space>a', function() require('my.finder').files() end, { desc = 'Finder: Find files' })
vim.keymap.set('n', '<Space>f', function()
  local config_parent = vim.fn.fnamemodify(vim.fn.stdpath('config') .. '/..', ':p:h')
  require('my.finder').files_in_dir(config_parent)
end, { desc = 'Finder: Find files in dotfiles' })
vim.keymap.set('n', '<Space>g', function() require('my.finder').live_grep() end, { desc = 'Finder: Live grep' })
vim.keymap.set('n', 'gnb', function() require('my.finder').git_branches() end, { desc = 'Finder: Git branches' })
vim.keymap.set('n', '<Space>b', function() require('my.finder').buffers() end, { desc = 'Finder: Buffers' })
vim.keymap.set('n', '<Space>h', function() require('my.finder').help_tags() end, { desc = 'Finder: Help tags' })
vim.keymap.set('n', '<Space>m', function() require('my.finder').manpages() end, { desc = 'Finder: Man pages' })
vim.keymap.set('n', '<Space>o', function() require('my.finder').oldfiles() end, { desc = 'Finder: Oldfiles' })
vim.keymap.set('n', '<Space>r', function() require('my.finder').resume() end, { desc = 'Finder: Resume' })

return {}
