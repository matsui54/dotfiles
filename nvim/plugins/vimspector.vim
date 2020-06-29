nmap <F3> :call <SID>exit_debug_mode()<CR>
nmap <F4> <Plug>VimspectorRestart
nmap <F5> :call <SID>enter_debug_mode()<CR>
nmap <F6> <Plug>VimspectorToggleBreakpoint
nmap <Leader><F6> <Plug>VimspectorToggleConditionalBreakpoint
nmap <F7> <Plug>VimspectorStepOver
nmap <F8> <Plug>VimspectorStepInto
nmap <F9> <Plug>VimspectorStepOut
nmap <F10> <Plug>VimspectorAddFunctionBreakpoint

function! s:do_and_return(func)
  let s:win = win_getid()
  echomsg s:win
  let F = function(a:func)
  call F()
  call win_gotoid(s:win)
endfunction

function! s:enter_debug_mode() abort
  set mouse=n
  nmap <LeftMouse> <LeftMouse><CR>
  " :の前の<CR>はマウスクリックのズレをなくすため
  nnoremap <buffer> <CR> <CR>:call vimspector#ToggleBreakpoint()<CR>
  call vimspector#Continue()
endfunction

function! s:exit_debug_mode() abort
  set mouse=
  nnoremap <LeftMouse> <LeftMouse>
  nnoremap <CR> <CR>
  VimspectorReset
endfunction
