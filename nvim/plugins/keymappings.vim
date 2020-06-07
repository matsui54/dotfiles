inoremap <silent> jj <ESC>

nnoremap <expr><F5> (&filetype=='vim') ? ":w <bar> :source %<CR>" 
			\: (&filetype=='python') ? ":wa <bar> :!python3 %" 
			\: ":wa <bar> :wincmd t <bar> :QuickRun <stdin.txt <CR>"
nnoremap <expr><silent> <Up> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd -<CR>" : ":wincmd +<CR>"
nnoremap <expr><silent> <Down> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd +<CR>" : ":wincmd -<CR>"
nnoremap <expr><silent> <Right> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd ><CR>" : ":wincmd <<CR>"
nnoremap <expr><silent> <Left> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd <<CR>" : ":wincmd ><CR>"
nnoremap <Space> :
nnoremap <silent> <C-j> gT
nnoremap <silent> <C-k> gt
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>
nnoremap G Gzz7<C-y>

cnoremap <silent><C-Space> :call system('fcitx-remote -c')<CR>:
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'
