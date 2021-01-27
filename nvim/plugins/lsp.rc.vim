lua require'lspconfig'.clangd.setup{}
lua require'lspconfig'.pyls.setup{}
lua require'lspconfig'.sumneko_lua.setup{}

lua << EOF
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
}
EOF

autocmd MyAutoCmd FileType python,cpp,c,lua call s:lsp_my_settings()

function! s:lsp_my_settings() abort
  setlocal signcolumn=yes
  nnoremap <buffer><silent> <c-]>     <cmd>lua vim.lsp.buf.definition()<CR>
  nnoremap <buffer><silent> K         <cmd>lua vim.lsp.buf.hover()<CR>
  nnoremap <buffer><silent> gD        <cmd>lua vim.lsp.buf.implementation()<CR>
  nnoremap <buffer><silent> 1gD       <cmd>lua vim.lsp.buf.type_definition()<CR>
  nnoremap <buffer><silent> gW        <cmd>lua vim.lsp.buf.workspace_symbol()<CR>
  nnoremap <buffer><silent> gd        <cmd>lua vim.lsp.buf.declaration()<CR>
  nnoremap <buffer><silent> <Leader>f <cmd>lua vim.lsp.buf.formatting()<CR>
  nnoremap <buffer><silent> <Leader>r <cmd>lua vim.lsp.buf.rename()<CR>
  " nnoremap <buffer><silent> <c-k> <cmd>lua vim.lsp.buf.signature_help()<CR>

  nnoremap <buffer><silent> g0        <cmd>Denite lsp/document_symbol -auto-action=preview_bat<CR>
  nnoremap <buffer><silent> gr        <cmd>Denite lsp/references -auto-action=preview_bat<CR>
  augroup MyLspSettings
    autocmd!
    autocmd CursorHold  <buffer> call s:safe_hightlight()
    autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
  augroup END
endfunction

function! s:safe_hightlight() abort
  try
    lua vim.lsp.buf.document_highlight()
  catch /^Vim\%((\a\+)\)\=:E5108/
  endtry
endfunction
