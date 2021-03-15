if has('vim_starting') && empty(argv())
  syntax off
endif

set title
set updatetime=500
set hidden
set laststatus=0
set signcolumn=yes

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

if vimrc#is_wsl()
  let clp_cmd = '/mnt/c/Users/harum/bin/win32yank.exe'
  let g:clipboard = {
        \   'name': 'myClipboard',
        \   'copy': {
        \      '+': clp_cmd . ' -i',
        \      '*': clp_cmd . ' -i',
        \    },
        \   'paste': {
        \      '*': clp_cmd . ' -o --lf',
        \      '+': clp_cmd . ' -o --lf',
        \   },
        \   'cache_enabled': 1,
        \ }
endif

set clipboard=unnamedplus

set ignorecase
set smartcase

set showmatch
set matchpairs+=<:>

set undofile

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
  set winblend=30
endif

if has('nvim')
  autocmd MyAutoCmd ColorScheme * call vimrc#color_settings()
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
  autocmd BufWrite * mksession! ~/.vim/sessions/saved_session.vim
  autocmd CmdwinEnter [:>] iunmap <buffer> <Tab>
  autocmd CmdwinEnter [:>] nunmap <buffer> <Tab>
  autocmd CursorHold * redrawtabline
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

" if vimrc#is_wsl()
"   command! Wslput :put =substitute(substitute(system('powershell.exe get-clipboard'), '\r', '', 'g'), '\n$', '', '')
" 
"   augroup Clip
"     autocmd!
"     autocmd TextYankPost * call system("clip.exe ", v:event.regcontents)
"   augroup END
" endif
