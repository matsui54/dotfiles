let g:deoplete#enable_at_startup = 1

autocmd InsertLeave * silent! pclose!

inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

" call deoplete#custom#var('tabnine', {
"      \ 'line_limit': 300,
"      \ 'max_num_results': 5,
"      \ })
" 
" call deoplete#custom#source('ale', 'rank', 1000)
" call deoplete#custom#source('tabnine', 'rank', 600)
