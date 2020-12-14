function! s:down(timer) abort
  execute "normal \<C-e>"
endfunction

function! s:up(timer) abort
  execute "normal \<C-y>"
endfunction

function! s:smooth_scroll(fn) abort
  let working_timer = get(s:, 'smooth_scroll_timer', 0)
  if working_timer
    call timer_stop(working_timer)
  endif
  let s:smooth_scroll_timer = timer_start(5, function('s:' . a:fn), {'repeat' : &scroll})
endfunction

function! smooth_scroll#up() abort
  call s:smooth_scroll('up')
endfunction

function! smooth_scroll#down() abort
  call s:smooth_scroll('down')
endfunction

