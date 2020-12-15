function! s:down(timer) abort
  execute "normal! \<C-e>j"
endfunction

function! s:up(timer) abort
  execute "normal! \<C-y>k"
endfunction

function! s:smooth_scroll(fn) abort
  let working_timer = get(s:, 'smooth_scroll_timer', 0)
  let stop_time = 5
  if !empty(timer_info(working_timer))
    call timer_stop(working_timer)
    let stop_time = 8
  endif
  let s:smooth_scroll_timer = timer_start(stop_time, function('s:' . a:fn), {'repeat' : &scroll})
endfunction

function! smooth_scroll#up() abort
  call s:smooth_scroll('up')
endfunction

function! smooth_scroll#down() abort
  call s:smooth_scroll('down')
endfunction

