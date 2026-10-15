-- Insert mode escape
vim.keymap.set('i', 'jj', '<Esc>')

-- Terminal mode window navigation
vim.keymap.set('t', '<A-h>', [[<C-\><C-n><C-w>h]])
vim.keymap.set('t', '<A-j>', [[<C-\><C-n><C-w>j]])
vim.keymap.set('t', '<A-k>', [[<C-\><C-n><C-w>k]])
vim.keymap.set('t', '<A-l>', [[<C-\><C-n><C-w>l]])

-- Normal mode window navigation
vim.keymap.set('n', '<A-h>', '<C-w>h')
vim.keymap.set('n', '<A-j>', '<C-w>j')
vim.keymap.set('n', '<A-k>', '<C-w>k')
vim.keymap.set('n', '<A-l>', '<C-w>l')

-- Window resizing with Arrow keys (based on screen position)
vim.keymap.set('n', '<Up>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[1] < 3 then
    vim.cmd('wincmd -')
  else
    vim.cmd('wincmd +')
  end
end, { silent = true, desc = 'Resize window up' })

vim.keymap.set('n', '<Down>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[1] < 3 then
    vim.cmd('wincmd +')
  else
    vim.cmd('wincmd -')
  end
end, { silent = true, desc = 'Resize window down' })

vim.keymap.set('n', '<Right>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[2] < 3 then
    vim.cmd('wincmd >')
  else
    vim.cmd('wincmd <')
  end
end, { silent = true, desc = 'Resize window right' })

vim.keymap.set('n', '<Left>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[2] < 3 then
    vim.cmd('wincmd <')
  else
    vim.cmd('wincmd >')
  end
end, { silent = true, desc = 'Resize window left' })

-- Shift + Arrow keys (5 or 10 lines step)
vim.keymap.set('n', '<S-Up>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[1] < 3 then
    vim.cmd('5wincmd -')
  else
    vim.cmd('5wincmd +')
  end
end, { silent = true, desc = 'Resize window up (step 5)' })

vim.keymap.set('n', '<S-Down>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[1] < 3 then
    vim.cmd('5wincmd +')
  else
    vim.cmd('5wincmd -')
  end
end, { silent = true, desc = 'Resize window down (step 5)' })

vim.keymap.set('n', '<S-Right>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[2] < 3 then
    vim.cmd('10wincmd >')
  else
    vim.cmd('10wincmd <')
  end
end, { silent = true, desc = 'Resize window right (step 10)' })

vim.keymap.set('n', '<S-Left>', function()
  local pos = vim.fn.win_screenpos(0)
  if pos[2] < 3 then
    vim.cmd('10wincmd <')
  else
    vim.cmd('10wincmd >')
  end
end, { silent = true, desc = 'Resize window left (step 10)' })

-- Command-line mode shortcut with ;
vim.keymap.set({ 'n', 'x' }, ';', ':')

-- Tabpage operations
vim.keymap.set('n', '<Space>t', '<cmd>tabe<CR>', { desc = 'Open new tab' })
vim.keymap.set('n', '<C-j>', 'gT', { desc = 'Previous tab' })
vim.keymap.set('n', '<C-k>', 'gt', { desc = 'Next tab' })

-- Improved G (jump to end and center scroll with offset)
vim.keymap.set('n', 'G', 'Gzz7<C-y>')

-- Change local directory to current file's parent
vim.keymap.set('n', '<Leader>cd', '<cmd>tcd %:h<CR>', { desc = 'Change tab-local dir to file directory' })

-- Visual line movement
vim.keymap.set({ 'n', 'x' }, 'j', 'gj')
vim.keymap.set({ 'n', 'x' }, 'k', 'gk')

-- Command-line navigation (Readline style)
vim.keymap.set('c', '<C-a>', '<Home>')
vim.keymap.set('c', '<C-e>', '<End>')
vim.keymap.set('c', '<C-n>', '<Down>')
vim.keymap.set('c', '<C-p>', '<Up>')
vim.keymap.set('c', '<C-y>', '<C-r>*')
vim.keymap.set('c', '<C-f>', '<Right>')
vim.keymap.set('c', '<C-b>', '<Left>')

-- User commands
vim.api.nvim_create_user_command('Undotree', function()
  vim.cmd('packadd nvim.undotree')
  vim.cmd('Undotree')
end, { desc = 'Load and toggle undotree' })

vim.api.nvim_create_user_command('DiffTool', function()
  vim.cmd('packadd nvim.difftool')
  vim.cmd('DiffTool')
end, { desc = 'Load and launch difftool' })
