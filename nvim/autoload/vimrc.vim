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
