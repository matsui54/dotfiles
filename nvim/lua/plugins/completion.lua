return {
  {
    'saghen/blink.cmp',
    dependencies = {
      'saghen/blink.lib',
      'rafamadriz/friendly-snippets',
    },
    build = function()
      -- build the fuzzy matcher, optionally add a timeout to `pwait(timeout_ms)`
      -- you can use `gb` in `:Lazy` to rebuild the plugin as needed
      require('blink.cmp').build():pwait()
    end,

  ---@module 'blink.cmp'
  ---@type blink.cmp.Config
  opts = {
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
      ['<C-n>'] = { function(cmp) return cmp.select_next({ auto_insert = false }) end, 'fallback_to_mappings' },
      ['<C-p>'] = { function(cmp) return cmp.select_prev({ auto_insert = false }) end, 'fallback_to_mappings' },
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
    sources = { default = { 'lsp', 'path', 'snippets', 'buffer' } },

    -- (Default) Rust fuzzy matcher for typo resistance and significantly better performance
    -- You may use a lua implementation instead by using `implementation = "lua"`
    -- See the fuzzy documentation for more information
    fuzzy = { implementation = "rust" },
    cmdline = {
      keymap = { preset = 'inherit' },
      completion = { menu = { auto_show = true } },
    },
  },

  },
}
