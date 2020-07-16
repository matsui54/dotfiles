set hidden
let g:LanguageClient_serverCommands = {
      \ 'cpp': ['clangd'],
      \ 'python': ['pyls'],
      \ }
let g:LanguageClient_loadSettings = 1
let g:LanguageClient_hasSnippetSupport = 0
let g:LanguageClient_useVirtualText = "CodeLens"
nnoremap K :call LanguageClient#textDocument_hover()<CR>
nnoremap F :call LanguageClient#textDocument_formatting()<CR>
nnoremap <F2> :call LanguageClient#textDocument_rename()<CR>
