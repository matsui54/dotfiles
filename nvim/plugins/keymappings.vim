inoremap <silent> jj <ESC>

nnoremap <expr><F5> (&filetype=='python') ? ":wa <bar> :!python3 %" : ":wa <bar> :wincmd t <bar> :QuickRun <stdin.txt <CR>"
nnoremap <silent> <Up> :wincmd +<CR>
nnoremap <silent> <Down> :wincmd -<CR>
nnoremap <silent> <Right> :wincmd ><CR>
nnoremap <silent> <Left> :wincmd <<CR>
nnoremap <Space> :
nnoremap <silent> <C-j> gT
nnoremap <silent> <C-k> gt
nnoremap <expr>d (&modifiable) ? "d" : "\<C-d>"
nnoremap <expr>u (&modifiable) ? "u" : "\<C-u>"

cnoremap <silent><C-Space> :call system('fcitx-remote -c')<CR>:
