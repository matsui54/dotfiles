set title
set updatetime=500
set hidden
set laststatus=2
set signcolumn=yes

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

if vimrc#is_wsl()
  let s:clp_cmd = 'win32yank'
  let g:clipboard = {
        \   'name': 'myClipboard',
        \   'copy': {
        \      '+': s:clp_cmd . ' -i',
        \      '*': s:clp_cmd . ' -i',
        \    },
        \   'paste': {
        \      '*': s:clp_cmd . ' -o --lf',
        \      '+': s:clp_cmd . ' -o --lf',
        \   },
        \   'cache_enabled': 1,
        \ }
endif

if !has('nvim')
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
endif

set clipboard=unnamedplus

set ignorecase
set smartcase

set showmatch
set matchpairs+=<:>

set undofile
if !has('nvim')
  let undodir = expand('~/.vim/undo')
  if !isdirectory(undodir)
    call mkdir(undodir)
  endif
  execute 'set undodir='.undodir
endif

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

augroup MyAutoCmd
  autocmd!
  autocmd ColorScheme * call vimrc#color_settings(expand('<amatch>'))
  autocmd VimEnter * let t:defx_index = 1 | let g:tab_idx = 1
  autocmd TabNew * let t:defx_index = s:get_defx_idx()
  autocmd CmdwinEnter [:>] iunmap <buffer> <Tab>
  autocmd CmdwinEnter [:>] nunmap <buffer> <Tab>
  autocmd CursorHold * redrawtabline
augroup END

colorscheme shirotelin

function! s:get_defx_idx()
  let g:tab_idx += 1
  return g:tab_idx
endfunction

" tabline setting
set showtabline=2
set tabline=%!tabline#MyTabLine()

set mouse=nv
