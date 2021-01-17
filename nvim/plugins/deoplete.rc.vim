let g:deoplete#enable_at_startup = 1

autocmd MyAutoCmd InsertLeave * silent! pclose!

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

call deoplete#custom#option({
      \ 'nofile_complete_filetypes': ['denite-filter', 'zsh'],
      \ 'num_processes': 4,
      \ 'refresh_always': v:true,
      \ })

" call deoplete#custom#var('tabnine', {
"      \ 'line_limit': 300,
"      \ 'max_num_results': 5,
"      \ })
 
" call deoplete#custom#source('tabnine', 'rank', 600)
