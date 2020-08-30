set hidden

let g:LanguageClient_serverCommands = {
      \ 'cpp': ['ccls'],
      \ 'python': ['pyls']
      \ }
let g:LanguageClient_loadSettings = 1
let g:LanguageClient_hasSnippetSupport = 0
let g:LanguageClient_diagnosticsEnable = 0

autocmd MyAutoCmd FileType python,cpp call s:lc_my_settings()

function! s:lc_my_settings() abort
  nnoremap <silent><buffer> K
        \ :call LanguageClient#textDocument_hover()<CR>
  nnoremap <silent><buffer> <Leader>f
        \ :call LanguageClient#textDocument_formatting()<CR>
  xnoremap <silent><buffer> <leader>f
        \ :call LanguageClient#textDocument_rangeFormatting()<CR>
  nnoremap <silent><buffer> <Leader>n
        \ :call LanguageClient#textDocument_rename()<CR>
  nnoremap <silent><buffer> <Leader>]
        \ :call LanguageClient#textDocument_definition()<CR>
  nnoremap <buffer> <Leader>r
        \ :Denite references<CR>
endfunction
