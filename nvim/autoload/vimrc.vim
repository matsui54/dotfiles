function! vimrc#on_insert_enter()
  if !exists("b:win_ime_con_is_insert")
    return
  endif
  if b:win_ime_con_is_insert == 0
    if b:win_ime_con_is_active == 1
       python3 wic.activate()
    endif
    let b:win_ime_con_is_insert = 1
  endif
endfunction

function! vimrc#disable_ime()
  if !exists("b:win_ime_con_is_insert")
    return
  endif
  if b:win_ime_con_is_insert
    python3 wic.on_leave(True)
  else
    python3 wic.on_leave(False)
  endif
  let b:win_ime_con_is_insert = 0
endfunction
