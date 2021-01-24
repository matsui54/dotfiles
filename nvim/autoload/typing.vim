let s:time_limit = 120
let s:counter = {'count' : 0}
highlight TypingError cterm=underline ctermfg=167 ctermbg=52 gui=underline guifg=#cc6666 guibg=#5f0000
highlight TypingCursor ctermfg=234 ctermbg=252 guifg=#161821 guibg=#c6c8d1

function! typing#start(v_start, v_end, enable_bs) abort
  let s:line_len = min([a:v_end - a:v_start + 1, 7])
  let s:lines = getbufline(bufnr(), a:v_start, a:v_start + s:line_len -1)
  let s:trimed_lines = map(copy(s:lines), 'trim(v:val)')
  let s:typing_continue = 1
  let s:counter.count = 0
  let s:list_cur_pos = []

  tabnew
  call setline(1, s:lines)
  setlocal filetype=vim-typing
  setlocal nobuflisted

  call s:before_start()
  echo 'Start!'

  let timer = timer_start(1000, s:counter.countdown, {'repeat' : -1})

  try
    let result = s:main(a:enable_bs)
  catch
    echomsg v:exception
  finally
    call timer_stop(timer)
    setlocal nomodifiable
    setlocal nomodified
    sleep 1
    nnoremap <buffer>q :q<CR>
    if exists('result')
      redraw
      for l in result
        echo l
      endfor
      " call s:show_floatingwindow(result)
    endif
  endtry
endfunction

function! s:before_start()
  for i in range(3, 1, -1)
    echo i
    sleep 1
  endfor
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

function! s:main(enable_bs) abort
  let s:cnt_typo = 0
  let cnt_type = 0

  if s:trimed_lines == []
    let cursor = s:next_pos([1, 1])
  else
    let cursor = [1, stridx(s:lines[0], s:trimed_lines[0]) + 1]
    call add(s:list_cur_pos, cursor)
  endif
  call matchaddpos('TypingCursor', [cursor])
  redraw

  while s:typing_continue
    let char = nr2char(getchar())
    if char ==# "\<Esc>"
      let s:typing_continue = 0
    elseif s:is_BS(char2nr(char))
      call matchaddpos('Normal', [cursor])
      let cursor = s:previous_pos()
      call matchaddpos('TypingCursor', [cursor])
    elseif char == s:lines[cursor[0]-1][cursor[1]-1]
      let cnt_type += 1
      call matchaddpos('Label', [cursor])
      let cursor = s:next_pos(cursor)
      if cursor[0] == 0
        break
      endif
      call matchaddpos('TypingCursor', [cursor])
    else
      call s:when_typo(cursor, a:enable_bs)
    endif
    redraw
  endwhile

  echo 'FINISH!'
  return [
        \'        typed  ' . (cnt_type + s:cnt_typo),
        \'      mistype  ' . (s:cnt_typo),
        \' elapsed time  ' . (s:counter.count/60 . ':' . s:counter.count % 60),
        \'        Speed  ' . printf('%s', printf('%.1f', cnt_type * (60.00 /s:counter.count))) . ' key/s'
        \]

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
  " for windows
  return a:char_nr == 8 || a:char_nr ==# "\<BS>"
endfunction

function! s:when_typo(cursor, enable_bs) abort
  let s:cnt_typo += 1
  let err_his = []
  let cursor = a:cursor

  call add(err_his, matchaddpos('TypingError', [cursor]))

  if a:enable_bs
    let cursor = s:next_pos(cursor)
    call add(err_his, matchaddpos('TypingError', [cursor]))
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
        let s:cnt_typo += 1
        let cursor = s:next_pos(cursor)
        if cursor[0] != 0
          call add(err_his, matchaddpos('TypingError', [cursor]))
        endif
      endif
      redraw
    endwhile
    call matchaddpos('TypingCursor', [cursor])
  endif
endfunction
