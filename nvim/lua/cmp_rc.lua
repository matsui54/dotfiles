local cmp = require "cmp"
cmp.setup {
  snippet = {
    expand = function(args)
      vim.fn["vsnip#anonymous"](args.body)
    end,
  },
  mapping = cmp.mapping.preset.insert({
    ['<C-b>'] = cmp.mapping.scroll_docs(-4),
    ['<C-f>'] = cmp.mapping.scroll_docs(4),
    ['<C-Space>'] = cmp.mapping.complete(),
    ['<C-e>'] = cmp.mapping.abort(),
    ['<CR>'] = cmp.mapping.confirm({ select = true }),
    ['<Tab>'] = cmp.mapping.select_next_item(),
    ['<S-Tab>'] = cmp.mapping.select_prev_item(),
  }),

    sources = cmp.config.sources({
      { name = 'nvim_lsp' },
      { name = 'vsnip' },
    }, {
      { name = 'buffer' },
      { name = 'dictionary' },
      { name = 'skkeleton' },
    })
}

cmp.setup.filetype({ 'lua' }, {
  sources = cmp.config.sources({
    { name = 'nvim_lsp' },
    { name = 'nvim_lua' },
    { name = 'vsnip' },
  }, {
    { name = 'buffer' },
    { name = 'dictionary' },
  })
})

cmp.setup.cmdline('/', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = {
    { name = 'buffer' }
  }
})

cmp.setup.cmdline(':', {
  mapping = cmp.mapping.preset.cmdline(),
  sources = cmp.config.sources({
    { name = 'path' }
  }, {
    { name = 'cmdline' }
  })
})

-- 動かないっぽい
vim.cmd([[
augroup MyCmpSkkeleton
  autocmd!
  autocmd User skkeleton-enable-pre call Cmp_skkeleton_pre()
  autocmd User skkeleton-disable-pre call Cmp_skkeleton_post()
augroup END
function! Cmp_skkeleton_pre() abort
  lua require "cmp".setup.view = { entries = 'native' }
endfunction
function! Cmp_skkeleton_post() abort
  lua require "cmp".setup.view = { entries = 'custom' }
endfunction
]])
