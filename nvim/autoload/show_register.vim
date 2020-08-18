let s:win = v:null
augroup RegisterComp
  autocmd!
augroup END

function! show_register#show() abort
  if s:win != v:null
    return
  endif
  let regs = ['+', '*', '"',
        \'0', '1', '2', '3', '4', '5', '6', '7', '8', '9',
        \'a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j',
        \'k', 'l', 'm', 'n', 'o', 'p', 'q', 'r', 's', 't',
        \'u', 'v', 'w', 'x', 'y', 'z',
        \'-', '.', ':', '#', '%', '/', '=']
  let lines = []
  let max_width = 0
  for reg in regs
    let register = s:getreg(reg)
    if register ==# ''
      continue
    endif

    let line = reg . ": " . register
    let max_width = max([max_width, len(line)])
    call add(lines, line[:96])
  endfor

  if lines == []
    return
  endif
  let cursor_row = win_screenpos(win_getid())[0]
        \ + getpos('.')[1]
        \ - line('w0')
  let screen_height = &lines
  if cursor_row < screen_height / 2
    let anchor = 'NW'
    let row = 1
  else
    let anchor = 'SW'
    let row = 0
  endif
  let s:buf = nvim_create_buf(v:false, v:true)
  call setbufline(s:buf, 1, lines)
  let s:win = nvim_open_win(s:buf, v:false,
        \ {'relative': 'cursor',
        \ 'width': min([max_width, 100]),
        \ 'height': len(lines),
        \ 'row': row,
        \ 'col': 1,
        \ 'anchor': anchor,
        \ 'style': "minimal"})

  call nvim_win_set_option(s:win, 'colorcolumn', '')
  call nvim_win_set_option(s:win, 'conceallevel', 2)

  call nvim_buf_set_option(s:buf, "buftype", "nofile")
  call nvim_buf_set_option(s:buf, "bufhidden", "delete")
  autocmd RegisterComp InsertLeave * call s:clear_fwin()
  autocmd RegisterComp InsertCharPre * call s:clear_fwin()
endfunction

function! s:clear_fwin()
  if s:win != v:null
    call nvim_win_close(s:win, v:false)
    let s:win = v:null
  endif
endfunction
" from Shougo/denite.nvim
function! s:getreg(reg) abort
  " Note: Substitute <80><fd>
  return substitute(getreg(a:reg, 1), '[\xfd\x80]', '', 'g')
endfunction
