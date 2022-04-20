if has('gui_running')
  set guioptions-=tT
  set guioptions-=m
  set guioptions-=rL
  set guioptions-=e
endif

if has('vim_starting')
  " 挿入モード時に非点滅の縦棒タイプのカーソル
  let &t_SI .= "\e[6 q"
  " ノーマルモード時に非点滅のブロックタイプのカーソル
  let &t_EI .= "\e[2 q"
  " 置換モード時に非点滅の下線タイプのカーソル
  let &t_SR .= "\e[4 q"
endif

augroup MyAutoCmd
  autocmd!
augroup END
if filereadable(expand('~/.vim/colors/iceberg.vim'))
  colorscheme iceberg
endif

" netrw settings
let g:netrw_preview=1
autocmd MyAutoCmd FileType netrw call s:netrw_my_settings()
function! s:netrw_my_settings()
  nmap <buffer>l <CR>
  nmap <buffer>h -
endfunction

nnoremap <expr> <Leader>d (&filetype=='vim') ? ':w <bar> :source %<CR>' : ':wa'

command! Wslput :r !win32yank.exe -o --lf

" yank
augroup Clip
  autocmd!
  autocmd TextYankPost * call system("win32yank.exe -i", v:event.regcontents)
augroup END

set title
set updatetime=500
set hidden
set laststatus=2
set signcolumn=yes

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

if has('vim_starting')
  " 挿入モード時に非点滅の縦棒タイプのカーソル
  let &t_SI .= "\e[6 q"
  " ノーマルモード時に非点滅のブロックタイプのカーソル
  let &t_EI .= "\e[2 q"
  " 置換モード時に非点滅の下線タイプのカーソル
  let &t_SR .= "\e[4 q"
endif
set wildmenu
set incsearch
set hlsearch

set clipboard=unnamedplus

set ignorecase
set smartcase

set showmatch
set matchpairs+=<:>

set termguicolors

set completeopt-=preview

set splitright

set helplang=en,ja
language en_US.utf8

if filereadable(expand('/usr/share/dict/words'))
  set dictionary=/usr/share/dict/words
endif

if exists('&inccommand')
  set inccommand=nosplit
endif

if exists('&pumblend')
  set pumblend=30
endif

if exists('&winblend')
  set winblend=10
endif

" Don't show too many items
set pumheight=15

set mouse=nv

inoremap jj <Esc>

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

" stop highlighting for search
nnoremap <silent> <C-l> <cmd>nohlsearch<CR><C-l>

" improved G
nnoremap G Gzz7<C-y>

"change local directory
nnoremap <Leader>cd <cmd>tcd %:h<CR>

" viml formatting
function! s:format_viml()
  let tmp = winsaveview()
  normal! ggVG=
  call winrestview(tmp)
endfunction
nnoremap <silent> <Leader>f <cmd>call <SID>format_viml()<CR>

" from nelstrom/vim-visual-star-search
function! s:VSetSearch(cmdtype)
  let temp = @"
  norm! y
  let @/ = '\V' . substitute(escape(@", a:cmdtype.'\'), '\n', '\\n', 'g')
  let @" = temp
endfunction

xnoremap * <cmd>call <SID>VSetSearch('/')<CR>/<C-R>=@/<CR><CR>
xnoremap # <cmd>call <SID>VSetSearch('?')<CR>?<C-R>=@/<CR><CR>

nnoremap j gj
nnoremap k gk
xnoremap j gj
xnoremap k gk

" for repeating indentation
xnoremap <silent> > ><cmd>call <SID>improved_indent()<CR>gv
xnoremap <silent> < <<cmd>call <SID>improved_indent()<CR>gv
function! s:improved_indent()
  augroup my_indent
    autocmd cursormoved * call s:exit_indent_mode()
  augroup END
  let s:moved = v:false
endfunction
function! s:exit_indent_mode()
  if s:moved
    execute "normal! \<C-c>"
    autocmd! my_indent
    let s:moved = v:false
  else
    let s:moved = v:true
  endif
endfunction

" insert parent directory of current file
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:p:h').'/' : '%%'

cnoremap <C-a> <Home>
cnoremap <C-e> <End>
cnoremap <C-n> <Down>
cnoremap <C-p> <Up>
cnoremap <C-y> <C-r>*
cnoremap <C-f> <Right>
cnoremap <C-b> <Left>
