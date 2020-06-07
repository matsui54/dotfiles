let g:ale_linters = {
			\'cpp': ['clangd'],
			\'python': ['pyls'],
			\'vim': ['vint']
			\}
let g:ale_fixers = {
			\'cpp':['clang-format'],
			\'python':['black']
			\}

nnoremap <Leader>f :ALEFix <CR>
nnoremap <Leader>gd :ALEGoToDefinition <CR>
nnoremap <Leader>h :ALEHover <CR>
nnoremap <Leader>rn :ALERename <CR>
nnoremap <expr><C-]> (count(['cpp', 'python'], &filetype)) ?
      \":ALEGoToDefinition<CR>"
      \: "<C-]>"
