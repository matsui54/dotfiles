let g:ale_linters = {
			\'cpp': ['clangd'],
			\'python': ['pyls']
			\}
let g:ale_fixers = {
			\'cpp':['clang-format'],
			\'python':['black']
			\}

nnoremap <Leader>f :ALEFix <CR>
nnoremap <Leader>gd :ALEGoToDefinition <CR>
nnoremap <Leader>h :ALEHover <CR>
nnoremap <Leader>rn :ALERename <CR>
