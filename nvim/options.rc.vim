if has('vim_starting') && empty(argv())
  syntax off
endif

set title
set updatetime=300
set hidden
set laststatus=0

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

if !vimrc#is_wsl()
  set clipboard=unnamedplus
endif

set ignorecase
set smartcase

set showmatch
set matchpairs+=<:>

set undofile

set termguicolors

set completeopt-=preview

set splitright

set helplang=en,ja

if filereadable(expand('~/dotfiles/nvim/dict/10k.txt'))
  set dictionary=~/dotfiles/nvim/dict/10k.txt
endif

if exists('&inccommand')
  set inccommand=nosplit
endif

if exists('&pumblend')
  set pumblend=30
endif

if exists('&winblend')
  set winblend=30
endif

if has('nvim')
  function! My_highlight_settings() abort
    highlight TabLineSel guifg=#ffffff
    highlight TabLineFill guifg=#b8b8b8
    highlight clear MatchParen
    highlight MatchParen cterm=underline, gui=underline
    highlight MyTabHi cterm=underline, gui=NONE, guifg=#737373
    highlight EndOfBuffer guifg=#454545
    highlight SignColumn guibg=#191c32
  endfunction
  autocmd MyAutoCmd ColorScheme * call My_highlight_settings()
  colorscheme iceberg
endif

if has('unix') && !vimrc#is_wsl()
  augroup im_change
    autocmd!
    autocmd InsertEnter * call system('fcitx-remote -c')
    autocmd InsertLeave * call system('fcitx-remote -o')
    autocmd VimLeave * call system('fcitx-remote -c')
    autocmd CmdlineLeave * call system('fcitx-remote -o')
    autocmd CompleteChanged * call system('fcitx-remote -c')
  augroup END
elseif vimrc#is_windows() && has('nvim')
  " for windows
  augroup im_change
    autocmd!
    autocmd BufWinEnter * let b:win_ime_con_is_active = 0
    autocmd BufWinEnter * let b:win_ime_con_is_insert = 0
    autocmd InsertEnter * call vimrc#on_insert_enter()
    autocmd InsertLeave * call vimrc#disable_ime()
    autocmd CmdlineLeave * call vimrc#disable_ime()
  augroup END
endif

augroup MyAutoCmd
  autocmd VimEnter * let t:defx_index = 1 | let g:tab_idx = 1
  autocmd TabNew * let t:defx_index = s:get_defx_idx()
  if !vimrc#is_windows()
    autocmd VimLeavePre,BufWrite * mksession! ~/.vim/sessions/saved_session.vim
  endif
  autocmd CmdwinEnter [:>] iunmap <buffer> <Tab>
  autocmd CmdwinEnter [:>] nunmap <buffer> <Tab>
  autocmd FileType,Syntax,BufNewFile,BufNew,BufRead *?
        \ call vimrc#on_filetype()
augroup END

function! s:get_defx_idx()
  let g:tab_idx += 1
  return g:tab_idx
endfunction

" tabline setting
set showtabline=2
set tabline=%!tabline#MyTabLine()
