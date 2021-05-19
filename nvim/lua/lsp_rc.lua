local on_attach = function(client)
  vim.wo.signcolumn = 'yes'
  local maps = {
    {'n', '<c-]>',     '<cmd>lua vim.lsp.buf.definition()<CR>'},
    {'n', 'K',         '<cmd>lua vim.lsp.buf.hover()<CR>'},
    {'n', 'gD',        '<cmd>lua vim.lsp.buf.implementation()<CR>'},
    {'n', '1gD',       '<cmd>lua vim.lsp.buf.type_definition()<CR>'},
    {'n', 'gW',        '<cmd>lua vim.lsp.buf.workspace_symbol()<CR>'},
    {'n', 'gd',        '<cmd>lua vim.lsp.buf.declaration()<CR>'},
    {'n', '<Leader>f', '<cmd>lua vim.lsp.buf.formatting()<CR>'},
    {'n', '<Leader>r', '<cmd>lua vim.lsp.buf.rename()<CR>'},
    {'n', 'gl',        '<cmd>lua vim.lsp.buf.document_highlight()<CR>'},
    {'n', 'gm',        '<cmd>lua vim.lsp.diagnostic.show_line_diagnostics()<CR>'},
    {'n', 'g0',        '<cmd>Denite lsp/document_symbol -auto-action=highlight<CR>'},
    {'n', 'gr',        '<cmd>Denite lsp/references -auto-action=preview_bat<CR>'},
  }
  for _, map in ipairs(maps) do
    vim.api.nvim_buf_set_keymap(0, map[1], map[2], map[3], {noremap = true})
  end

  vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
      virtual_text = false,
    }
  )

  vim.api.nvim_exec(
  [[
    augroup MyLspSettings
      autocmd!
      autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
    augroup END
  ]],
  false)
end

require'lspconfig'.clangd.setup{on_attach = on_attach}
require'lspconfig'.pyls.setup{on_attach = on_attach}
require'lspconfig'.rls.setup{on_attach = on_attach}
require'lspconfig'.svls.setup{on_attach = on_attach}
require'lspconfig'.texlab.setup{on_attach = on_attach}
require'lspconfig'.denols.setup{on_attach = on_attach}

local sumneko_root_path = vim.fn.stdpath('cache')..'/lspconfig/sumneko_lua/lua-language-server'
local sumneko_binary = sumneko_root_path.."/bin/Linux/lua-language-server"

require'lspconfig'.sumneko_lua.setup {
  cmd = {sumneko_binary, "-E", sumneko_root_path .. "/main.lua"};
  settings = {
    Lua = {
      runtime = {
        -- Tell the language server which version of Lua you're using (most likely LuaJIT in the case of Neovim)
        version = 'LuaJIT',
        -- Setup your lua path
        path = vim.split(package.path, ';'),
      },
      diagnostics = {
        -- Get the language server to recognize the `vim` global
        globals = {'vim'},
      },
      workspace = {
        -- Make the server aware of Neovim runtime files
        library = {
          [vim.fn.expand('$VIMRUNTIME/lua')] = true,
          [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true,
        },
      },
    },
  },
  on_attach = on_attach,
}
