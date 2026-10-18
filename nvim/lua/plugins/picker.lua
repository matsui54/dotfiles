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
          clear_query = '<C-u>',   -- 入力クエリを全消去 (コマンドラインの <C-u> 相当)
        },
        mappings = {
          i = {
            ['<C-a>'] = '<Home>',  -- 行頭へ移動
            ['<C-e>'] = '<End>',   -- 行末へ移動
            ['<C-f>'] = '<Right>', -- 右へ移動
            ['<C-b>'] = '<Left>',  -- 左へ移動
            ['<C-d>'] = '<Del>',   -- 1文字削除
            ['<C-h>'] = '<BS>',    -- バックスペース
            ['<C-k>'] = '<C-o>D',  -- カーソル位置から行末まで削除
            ['<C-y>'] = '<C-r>*',  -- クリップボード貼り付け
          },
        },
      }
    end,
    keys = {
      { '<Space>a', function() require('fff').find_files() end, desc = 'fff: Find files' },
      {
        '<Space>f',
        function()
          local config_parent = vim.fn.fnamemodify(vim.fn.stdpath('config') .. '/..', ':p:h')
          require('fff').find_files_in_dir(config_parent)
        end,
        desc = 'fff: Find files in dotfiles',
      },
      { '<Space>g', function() require('fff').live_grep() end, desc = 'fff: Live grep' },
      { 'ff', function() require('fff').find_files() end, desc = 'fff: Find files' },
    },
  },

  -- fzf-lua (buffers, help, oldfiles, ui_select, etc.)
  {
    'ibhagwan/fzf-lua',
    init = function()
      -- コマンドライン入力中の <C-t> で command_history を起動 (ddu の <C-t> 相当)
      vim.keymap.set('c', '<C-t>', function()
        local cmdline = vim.fn.getcmdline()
        vim.schedule(function()
          require('fzf-lua').command_history({ query = cmdline })
        end)
        return '<C-u><Esc>'
      end, { expr = true, silent = true, desc = 'fzf-lua: Command history' })
    end,
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
        command_history = {
          actions = {
            ['enter'] = fzf.actions.ex_run, -- Enter で常にコマンドライン編集状態にする
            ['ctrl-r'] = fzf.actions.ex_run_cr, -- 即時実行したい場合の代替キー
          },
        },
      })
      fzf.register_ui_select()
    end,
    keys = {
      { '<Space>b', function() require('fzf-lua').buffers() end, desc = 'fzf-lua: Buffers' },
      { '<Space>h', function() require('fzf-lua').help_tags() end, desc = 'fzf-lua: Help tags' },
      { '<Space>m', function() require('fzf-lua').manpages() end, desc = 'fzf-lua: Man pages' },
      { '<Space>o', function() require('fzf-lua').oldfiles() end, desc = 'fzf-lua: Oldfiles' },
      { '<Space>r', function() require('fzf-lua').resume() end, desc = 'fzf-lua: Resume' },
    },
  },
}
