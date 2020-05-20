let g:deoplete#enable_at_startup = 1

autocmd InsertLeave * silent! pclose!

inoremap <expr><S-TAB>  pumvisible() ? "\<C-p>" : "\<C-h>"
