inoremap jj <Esc>

if has('nvim')
  tnoremap <A-h> <C-\><C-N><C-w>h
  tnoremap <A-j> <C-\><C-N><C-w>j
  tnoremap <A-k> <C-\><C-N><C-w>k
  tnoremap <A-l> <C-\><C-N><C-w>l
endif

nnoremap <Leader>m <cmd>wa <Bar> make<CR>

nnoremap <A-h> <C-w>h
nnoremap <A-j> <C-w>j
nnoremap <A-k> <C-w>k
nnoremap <A-l> <C-w>l

" resize window using arrow key
nnoremap <expr><silent> <Up> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd -<CR>" : ":wincmd +<CR>"
nnoremap <expr><silent> <Down> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd +<CR>" : ":wincmd -<CR>"
nnoremap <expr><silent> <Right> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd ><CR>" : ":wincmd <<CR>"
nnoremap <expr><silent> <Left> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd <<CR>" : ":wincmd ><CR>"

nnoremap <expr><silent> <S-Up> (win_screenpos(win_getid())[0] < 3) ?
      \":5wincmd -<CR>" : ":5wincmd +<CR>"
nnoremap <expr><silent> <S-Down> (win_screenpos(win_getid())[0] < 3) ?
      \":5wincmd +<CR>" : ":5wincmd -<CR>"
nnoremap <expr><silent> <S-Right> (win_screenpos(win_getid())[1] < 3) ?
      \":10wincmd ><CR>" : ":10wincmd <<CR>"
nnoremap <expr><silent> <S-Left> (win_screenpos(win_getid())[1] < 3) ?
      \":10wincmd <<CR>" : ":10wincmd ><CR>"

nnoremap ; :
xnoremap ; :

" move around tabpages
nnoremap <C-j> gT
nnoremap <C-k> gt
nnoremap <Space><C-j> <cmd>tabmove -<CR>
nnoremap <Space><C-k> <cmd>tabmove +<CR>
nnoremap <Space>t <cmd>tabe<CR>

" improved G
nnoremap G Gzz7<C-y>

"change local directory
nnoremap <Leader>cd <cmd>tcd %:h<CR>

" multiple search
nnoremap <expr> <Leader>/ multi_search#hl_last_match() . "/"
nnoremap <expr> <Leader>* multi_search#hl_last_match() . "*"
nmap <expr> <Leader>l "\<C-l>" . multi_search#delete_search_all()

nmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
nmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>
vmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
vmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>

" for sandwich.vim
nmap s <Nop>
xmap s <Nop>

nnoremap j gj
nnoremap k gk
xnoremap j gj
xnoremap k gk

" insert parent directory of current file
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:p:h').'/' : '%%'

cnoremap <C-a> <Home>
cnoremap <C-e> <End>
cnoremap <C-n> <Down>
cnoremap <C-p> <Up>
cnoremap <C-y> <C-r>*
cnoremap <C-f> <Right>
cnoremap <C-b> <Left>

" commands
command! DeinClean :call map(dein#check_clean(), "delete(v:val, 'rf')") |
      \ call dein#recache_runtimepath()

command! Undotree :packadd nvim.undotree | Undotree                                                                                                                                                     
command! DiffTool :packadd nvim.difftool | DiffTool                                                                                                                                                     
