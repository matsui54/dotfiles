return {
  {
    'saghen/blink.cmp',
    dependencies = {
      'saghen/blink.lib',
      'rafamadriz/friendly-snippets',
    },
    -- blink.cmp v2 の .build() は外部ダウンロードを行わずローカルの cargo build --release を実行する
    build = function()
      require('blink.cmp').build():pwait(60000)
    end,

    ---@module 'blink.cmp'
    ---@type blink.cmp.Config
    opts = {
      enabled = function()
        local ok, skkelua = pcall(require, 'skkelua')
        if ok and skkelua.is_enabled() then
          return false
        end
        return vim.bo.buftype ~= 'prompt' and vim.b.completion ~= false
      end,
      keymap = {
        preset = 'none',

        -- ddc の <Tab> 挙動:
        -- 1. 補完メニュー表示中: 未選択なら1番目を選択して確定 (select_and_accept)
        -- 2. スニペットプレースホルダがあれば次へジャンプ
        -- 3. 単語の後ろなら補完を手動トリガー (manual_complete)
        -- 4. 行頭または空白直後なら通常の <Tab>
        ['<Tab>'] = {
          'select_and_accept',
          'snippet_forward',
          function(cmp)
            local col = vim.fn.col('.') - 1
            if col == 0 or vim.fn.getline('.'):sub(col, col):match('%s') then
              return
            end
            return cmp.show()
          end,
          'fallback',
        },
        ['<S-Tab>'] = { 'snippet_backward', 'fallback' },

        -- ddc の候補移動・確定・キャンセル
        ['<C-n>'] = { function(cmp) return cmp.select_next({ auto_insert = false }) end, 'fallback' },
        ['<C-p>'] = { function(cmp) return cmp.select_prev({ auto_insert = false }) end, 'fallback' },
        ['<C-y>'] = { 'select_and_accept', 'fallback' },
        ['<C-e>'] = { 'cancel', 'fallback' },

        -- <CR> は確定にせず通常の改行とする (ddc 仕様)
        ['<CR>'] = { 'fallback' },

        -- ddc の <C-x><C-f> でファイルパス補完を手動呼び出し
        ['<C-x><C-f>'] = {
          function(cmp)
            cmp.show({ providers = { 'path' } })
          end,
        },

        -- 矢印キー
        ['<Up>'] = { 'select_prev', 'fallback' },
        ['<Down>'] = { 'select_next', 'fallback' },

        -- ドキュメントスクロール & シグネチャヘルプ
        ['<C-b>'] = { 'scroll_documentation_up', 'fallback' },
        ['<C-f>'] = { 'scroll_documentation_down', 'fallback' },
        ['<C-k>'] = { 'show_signature', 'hide_signature', 'fallback' },
        ['<C-space>'] = { 'show', 'show_documentation', 'hide_documentation' },
      },

      -- (Default) Only show the documentation popup when manually triggered
      completion = { documentation = { auto_show = true, auto_show_delay_ms = 500 }, },

      -- (Default) list of enabled providers defined so that you can extend it
      -- elsewhere in your config, without redefining it, due to `opts_extend`
      sources = {
        default = { 'lsp', 'path', 'snippets', 'buffer' },
        providers = {
          lsp = { fallbacks = {} }
        }
      },

      fuzzy = {
        implementation = 'prefer_rust',
      },
      cmdline = {
        keymap = {
          preset = 'none',
          ['<Tab>'] = { 'show_and_insert_or_accept_single', 'select_next' },
          ['<S-Tab>'] = { 'show_and_insert_or_accept_single', 'select_prev' },

          ['<C-y>'] = { 'select_and_accept', 'fallback' },
          ['<C-e>'] = { 'cancel', 'fallback' },
        },
        completion = {
          menu = { auto_show = true },
          list = { selection = { preselect = false } },
        },
      },
    },
  },

  -- kjuq/skkelua.nvim (SKK 日本語入力)
  {
    'kjuq/skkelua.nvim',
    lazy = false,
    dependencies = {
      'skk-dev/dict',
    },
    config = function()
      local skkelua = require('skkelua')

      vim.keymap.set({ 'i', 'c', 't' }, '<C-j>', '<Plug>(skkelua-toggle)', { desc = 'SKK: Toggle skkelua' })

      -- <BS>/<C-h> で変換候補を戻す
      skkelua.register_keymap('henkan', '<BS>', 'henkanBackward')
      skkelua.register_keymap('henkan', '<C-h>', 'henkanBackward')
      skkelua.register_keymap('henkan', 'x', '')

      skkelua.config({
        globalDictionaries = {
          vim.fs.joinpath(vim.fn.stdpath('data'), 'lazy', 'dict', 'SKK-JISYO.L'),
        },
        completionRankFile = vim.fs.joinpath(vim.fn.stdpath('state'), 'skkelua', 'rank'),
        completion = {
          enabled = true,
          insertOnSelect = true,
          deferOkuri = true,
        },
        indicator = {
          alwaysShown = false,
        },
      })

      skkelua.register_kanatable('rom', {
        ['z '] = { '\u{3000}', '' },
        ['jj'] = 'escape',
        ['z,'] = { '，', '' },
        ['z.'] = { '．', '' },
        ['z9'] = { '（', '' },
        ['z0'] = { '）', '' },
        ['~'] = { '～', '' },
      })

      -- 有効化・無効化時に blink.cmp のメニューが開いていれば閉じる
      local group = vim.api.nvim_create_augroup('my.skkelua', { clear = true })
      vim.api.nvim_create_autocmd('User', {
        group = group,
        pattern = { 'skkelua-enable-pre', 'skkelua-disable-post' },
        callback = function()
          local ok, blink = pcall(require, 'blink.cmp')
          if ok and blink.is_visible() then
            blink.hide()
          end
        end,
      })
    end,
  },
}
