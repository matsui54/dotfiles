let s:default_stop_time = (vimrc#is_windows() ? 5 : 10)

function! s:down(timer) abort
  execute "normal! 3\<C-e>3j"
endfunction

function! s:up(timer) abort
  execute "normal! 3\<C-y>3k"
endfunction

function! s:smooth_scroll(fn) abort
  let working_timer = get(s:, 'smooth_scroll_timer', 0)
  let stop_time = s:default_stop_time
  if !empty(timer_info(working_timer))
    call timer_stop(working_timer)
    let stop_time = s:default_stop_time + 2
  endif
  if (a:fn ==# 'down' && line('$') == line('w$')) ||
        \ (a:fn ==# 'up' && line('w0') == 1)
    return
  endif
  let s:smooth_scroll_timer = timer_start(stop_time, function('s:' . a:fn), {'repeat' : &scroll/3})
endfunction

function! smooth_scroll#up() abort
  call s:smooth_scroll('up')
endfunction

function! smooth_scroll#down() abort
  call s:smooth_scroll('down')
endfunction
