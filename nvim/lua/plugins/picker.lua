return {
  -- fff (Files & Live Grep)
  {
    'dmtrKovalenko/fff',
    build = function()
      require('fff.download').download_or_build_binary()
    end,
    init = function()
      vim.g.fff = {
        lazy_sync = true,
        debug = { enabled = true, show_scores = true },
        keymaps = {
          select = '<CR>',
          select_vsplit = '<C-v>', -- 垂直分割 (ddu の E 相当)
          select_split = '<C-s>',  -- 水平分割 (ddu の S 相当)
          select_tab = '<C-t>',    -- タブ (ddu の t 相当)
        },
      }
    end,
    keys = {
      { '<Space>a', function() require('fff').find_files() end, desc = 'fff: Find files' },
      { '<Space>g', function() require('fff').live_grep() end, desc = 'fff: Live grep' },
      { 'ff', function() require('fff').find_files() end, desc = 'fff: Find files' },
    },
  },

  -- fzf-lua (buffers, help, oldfiles, ui_select, etc.)
  {
    'ibhagwan/fzf-lua',
    config = function()
      local fzf = require('fzf-lua')
      fzf.setup({
        actions = {
          files = {
            ['enter'] = fzf.actions.file_edit,
            ['ctrl-v'] = fzf.actions.file_vsplit, -- 垂直分割 (ddu の E 相当)
            ['ctrl-s'] = fzf.actions.file_split,  -- 水平分割 (ddu の S 相当)
            ['ctrl-x'] = fzf.actions.file_split,  -- 水平分割 (端末のC-sバッティング対策)
            ['ctrl-t'] = fzf.actions.file_tabedit, -- タブ (ddu の t 相当)
          },
        },
      })
      fzf.register_ui_select()
    end,
    keys = {
      { '<Space>b', function() require('fzf-lua').buffers() end, desc = 'fzf-lua: Buffers' },
      { '<Space>h', function() require('fzf-lua').help_tags() end, desc = 'fzf-lua: Help tags' },
      { '<Space>o', function() require('fzf-lua').oldfiles() end, desc = 'fzf-lua: Oldfiles' },
      { '<Space>r', function() require('fzf-lua').resume() end, desc = 'fzf-lua: Resume' },
    },
  },
}
