function! vimrc#on_insert_enter() abort
  if !exists('b:win_ime_con_is_insert')
    return
  endif
  if b:win_ime_con_is_insert == 0
    if b:win_ime_con_is_active == 1
      call _activate_ime()
    endif
    let b:win_ime_con_is_insert = 1
  endif
endfunction

function! vimrc#disable_ime() abort
  if !exists('b:win_ime_con_is_insert')
    return
  endif
  if b:win_ime_con_is_insert
    call _disable_ime(v:true)
  else
    call _disable_ime(v:false)
  endif
  let b:win_ime_con_is_insert = 0
endfunction

function! vimrc#is_wsl() abort
  return executable('cmd.exe') && isdirectory('/mnt/c')
endfunction

function! vimrc#is_windows() abort
  return has('win32') || has('win64')
endfunction

function! vimrc#on_filetype() abort
  if execute('filetype') =~# 'OFF'
    " Lazy loading
    silent! filetype plugin indent on
    syntax enable
    filetype detect
    call vimrc#color_settings()
  endif
endfunction

function! vimrc#color_settings() abort
  highlight TabLineSel guifg=#ffffff
  highlight TabLineFill guifg=#b8b8b8
  highlight clear MatchParen
  highlight MatchParen cterm=underline, gui=underline
  highlight MyTabHi cterm=underline, gui=NONE, guifg=#737373
  highlight EndOfBuffer guifg=#454545
  highlight SignColumn guibg=#191c32
endfunction
