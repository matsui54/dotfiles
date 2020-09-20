let s:time_limit = 120
let s:counter = {'count' : 0}

function! typing#start(v_start, v_end, enable_bs) abort
  let s:line_len = min([a:v_end - a:v_start + 1, 7])
  let s:lines = getbufline(bufnr(), a:v_start, a:v_start + s:line_len -1)
  let s:trimed_lines = map(copy(s:lines), 'trim(v:val)')
  let s:typing_continue = 1
  let s:counter.count = 0
  let s:list_cur_pos = []

  let cnt_typo = 0
  let cnt_type = 0

  tabnew
  setlocal nobuflisted
  setlocal filetype=vim-typing
  call setline(1, s:lines)

  call s:before_start()
  echo 'Start!'

  let timer = timer_start(1000, s:counter.countdown, {'repeat' : -1})

  try
    if s:trimed_lines == []
      let cursor = s:next_pos([1, 1])
    else
      let cursor = [1, stridx(s:lines[0], s:trimed_lines[0]) + 1]
      call add(s:list_cur_pos, cursor)
    endif
    call matchaddpos('Cursor', [cursor])
    redraw

    while s:typing_continue
      let err_his = []

      let char = nr2char(getchar())
      if char ==# "\<Esc>"
        let s:typing_continue = 0
      elseif s:is_BS(char2nr(char))
        call matchaddpos('Normal', [cursor])
        let cursor = s:previous_pos()
        call matchaddpos('Cursor', [cursor])
      elseif char == s:lines[cursor[0]-1][cursor[1]-1]
        let cnt_type += 1
        call matchaddpos('Label', [cursor])
        let cursor = s:next_pos(cursor)
        if cursor[0] == 0
          break
        endif
        call matchaddpos('Cursor', [cursor])
      else
        let cnt_typo += 1
        call add(err_his, matchaddpos('Error', [cursor]))

        " operation executed when BS_enable = true
        if a:enable_bs
          let cursor = s:next_pos(cursor)
          call add(err_his, matchaddpos('Error', [cursor]))
          redraw
          while len(err_his) > 1
            let char_nr = getchar()
            if s:is_BS(char_nr)
              let cursor = s:previous_pos()
              call matchdelete(err_his[-1])
              call remove(err_his, -1)
            elseif char_nr ==# 27 " <Esc>
              let s:typing_continue = 0
              break
            else
              let cnt_typo += 1
              let cursor = s:next_pos(cursor)
              if cursor[0] != 0
                call add(err_his, matchaddpos('Error', [cursor]))
              endif
            endif
            redraw
          endwhile
          call matchaddpos('Cursor', [cursor])
        endif

      endif
      redraw
    endwhile

    echo 'FINISH!'
    call timer_stop(timer)
    redraw
    let result = [
          \'        typed  ' . (cnt_type + cnt_typo),
          \'      mistype  ' . (cnt_typo),
          \' elapsed time  ' . (s:counter.count/60 . ':' . s:counter.count % 60),
          \'        Speed  ' . printf('%s', printf('%.1f', cnt_type * (60.00 /s:counter.count))) . ' key/s'
          \]
    setlocal nomodifiable
    setlocal nomodified
    sleep 50m
    nnoremap <buffer>q :q<CR>
    call s:show_floatingwindow(result)

  catch
    call timer_stop(timer)
    echomsg v:exception
  endtry

endfunction

function! s:before_start()
  for i in range(3, 1, -1)
    echo i
    sleep 1
  endfor
endfunction

" returns the list of next cursor's position(1 based)
function! s:next_pos(cursor)
  let row = a:cursor[0]
  let col = a:cursor[1]

  if row == 0 && col ==0
    return [0, 0]
  endif

  " check if the cursor is at the end of the line
  if col >= len(s:trimed_lines[row -1]) + stridx(s:lines[row -1], s:trimed_lines[row - 1])
    if row == len(s:lines)
      return [0, 0]
    else
      let next_row = row + 1
      while s:trimed_lines[next_row -1] ==# ''
        if next_row == len(s:lines)
          return [0,0]
        endif
        let next_row += 1
      endwhile
      let res = [next_row, stridx(s:lines[next_row -1], s:trimed_lines[next_row -1]) + 1]
    endif
  else
    let res = [row, col+1]
  endif
  call add(s:list_cur_pos, res)
  return res
endfunction
function! s:previous_pos() abort
  if len(s:list_cur_pos) == 1
    return s:list_cur_pos[0]
  endif
  call remove(s:list_cur_pos, -1)
  return s:list_cur_pos[-1]
endfunction

function! s:counter.countdown(timer)
  let s:re_time = s:time_limit - self.count
  let self.count += 1
  if s:re_time >= 0
    call setline(s:line_len + 1, self.count)
    redraw
  else
    let s:typing_continue = 0
    call timer_stop(a:timer)
  endif
endfunction

function! s:show_floatingwindow(messages)
  " let width = float2nr(winwidth(0) * 0.8)
  let height = float2nr(winheight(0) * 0.8)
  let buf = nvim_create_buf(v:false, v:true)
  call nvim_buf_set_lines(buf, 0, -1, v:true, a:messages)
  let opts = {
        \'relative': 'editor',
        \'width': 30,
        \'height': height,
        \'col': winwidth(0)/2 - 15,
        \'row': 5,
        \'anchor': 'NW',
        \'style': 'minimal'
        \}
  let win = nvim_open_win(buf, 1, opts)
  setlocal nomodifiable
  nnoremap <buffer>q :q<CR>
endfunction

function! s:is_BS(char_nr) abort
  return a:char_nr == 8 || a:char_nr ==# "\<BS>"
endfunction
