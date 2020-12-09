lua require'lspconfig'.clangd.setup{}
lua require'lspconfig'.pyls.setup{}
lua require'lspconfig'.sumneko_lua.setup{}

autocmd MyAutoCmd FileType python,cpp,c,lua call s:lsp_my_settings()

function! s:lsp_my_settings() abort
  setlocal signcolumn=yes
  nnoremap <buffer><silent> <c-]>     <cmd>lua vim.lsp.buf.definition()<CR>
  nnoremap <buffer><silent> K         <cmd>lua vim.lsp.buf.hover()<CR>
  nnoremap <buffer><silent> gD        <cmd>lua vim.lsp.buf.implementation()<CR>
  nnoremap <buffer><silent> 1gD       <cmd>lua vim.lsp.buf.type_definition()<CR>
  nnoremap <buffer><silent> gr        <cmd>lua vim.lsp.buf.references()<CR>
  nnoremap <buffer><silent> g0        <cmd>lua vim.lsp.buf.document_symbol()<CR>
  nnoremap <buffer><silent> gW        <cmd>lua vim.lsp.buf.workspace_symbol()<CR>
  nnoremap <buffer><silent> gd        <cmd>lua vim.lsp.buf.declaration()<CR>
  nnoremap <buffer><silent> <Leader>f <cmd>lua vim.lsp.buf.formatting()<CR>
  " nnoremap <buffer><silent> <c-k> <cmd>lua vim.lsp.buf.signature_help()<CR>
endfunction
