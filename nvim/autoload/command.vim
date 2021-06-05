let g:command#history_path =
      \ get(g:, 'command#history_path', '~/.zsh_history')
let g:command#shell_history_max = 
      \ get(g:, 'command#shell_history_max', 1000)

let g:command#_bufnr = -1
let s:edit_bufnr = -1
let s:edit_winid = -1

function! command#open(cwd='.') abort
  let ids = win_findbuf(g:command#_bufnr)
  if !empty(ids) && win_getid() != ids[0]
    call win_gotoid(ids[0])
    call cursor(line('$'), 0)
  endif

  call s:switch_edit_buffer(a:cwd)

  call s:init_edit_buffer()

  if getline('$') !=# ''
    call append(line('$'), '')
  endif
  call cursor(line('$'), 0)
  startinsert!
endfunction

function! s:switch_edit_buffer(cwd) abort
  if win_findbuf(s:edit_bufnr) == [s:edit_winid]
    call win_gotoid(s:edit_winid)
    return
  endif

  let cwd = fnamemodify(a:cwd, ':p')
  let edit_bufname = 'command://' . cwd
  " call nvim_open_win(bufnr('%'), v:true, {
  "      \ 'relative': 'win',
  "      \ 'win': win_getid(),
  "      \ 'anchor': "SW",
  "      \ 'row': str2nr(winheight(0)),
  "      \ 'col': str2nr(0),
  "      \ 'width': winwidth(0),
  "      \ 'height': 5,
  "      \ })
  let bufnr = bufadd(edit_bufname)
  botright split
  execute bufnr 'buffer'
  resize 7

  if line('$') == 1
    call append(0, s:get_histories())
  endif

  execute 'lcd ' a:cwd

  let s:edit_winid = win_getid()
  let s:edit_bufnr = bufnr('%')
endfunction

function! s:init_edit_buffer() abort
  setlocal bufhidden=hide
  setlocal buftype=nofile
  setlocal nolist
  setlocal nobuflisted
  setlocal nofoldenable
  setlocal foldcolumn=0
  setlocal colorcolumn=
  setlocal nonumber
  setlocal norelativenumber
  setlocal noswapfile

  nnoremap <buffer><silent> <Plug>(command_execute_line)
        \ :<C-u>call <SID>execute_line()<CR>
  inoremap <buffer><silent> <Plug>(command_execute_line)
        \ <ESC>:call <SID>execute_line()<CR>

  nnoremap <buffer><silent> <Plug>(command_quit)
        \ :<C-u>close<CR>

  nmap <buffer><CR> <Plug>(command_execute_line)
  imap <buffer><CR> <Plug>(command_execute_line)
  nmap <buffer> q   <Plug>(command_quit)

  setlocal filetype=zsh
endfunction

function! s:execute_line() abort
  stopinsert
  let line = getline('.')
  execute '!' line
endfunction

function! s:get_histories() abort
  let history_path = expand(g:command#history_path)
  if !filereadable(history_path)
    return []
  endif

  let histories = readfile(history_path)
  if g:command#shell_history_max > 0 &&
      \ len(histories) > g:command#shell_history_max
      let histories = histories[-g:command#shell_history_max :]
  endif
  return map(histories,
        \ { _, val -> substitute(
        \  val, '^\%(\d\+/\)\+[:[:digit:]; ]\+\|^[:[:digit:]; ]\+', '', '')
        \ })
endfunction
