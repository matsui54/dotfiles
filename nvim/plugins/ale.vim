let g:ale_linters = {
			\'cpp': ['clangd', 'ccls'],
			\'python': ['pyls', 'flake8', 'mypy'],
			\'vim': ['vint']
			\}
let g:ale_fixers = {
			\'cpp':['clang-format'],
			\'python':['autopep8', 'isort']
			\}

nnoremap <Leader>f :ALEFix <CR>
nnoremap <Leader>] :ALEGoToDefinition <CR>
" nnoremap <Leader>h :ALEHover <Bar> :call <SID>ale_my_hover_config()<CR>
nnoremap <Leader>h :ALEHover<CR>
nnoremap <Leader>r :ALEFindReferences <CR>
nnoremap <Leader>n :ALERename <CR>

let g:ale_hover_to_preview=1

" setting for ALEFindReferences---------------------------------
augroup ale
  autocmd!
  autocmd FileType ale-preview-selection call s:ale_my_ref_config()
augroup END

function! s:ale_my_ref_config() abort
  setlocal cursorline
  nnoremap <silent><buffer> f
        \ :call <SID>enter_ale_reference_mode()<CR>
endfunction

function! s:enter_ale_reference_mode() abort
  call s:show_ref_from_ale()
  nnoremap <buffer><silent> q :call <SID>my_ale_close_ref()<CR>
  augroup ale_ref
    autocmd CursorMoved <buffer> call s:show_ref_from_ale()
  augroup END
endfunction

function! s:show_ref_from_ale() abort
  let line = getbufline('%', getpos('.')[1])[0]
  let [file_path, row, col] = split(line, ':')
  let fwin_config = {
          \ 'relative': 'cursor', 
          \ 'height': 20,
          \ 'width': 80,
          \ 'row': 5,
          \ 'col': 0,
          \ 'anchor':'NW'
          \ }

  if exists('w:my_config_winid') && win_id2win(w:my_config_winid)
    let s:f_win = w:my_config_winid
    call nvim_win_set_config(w:my_config_winid, fwin_config)
    call win_gotoid(w:my_config_winid)
  else
    unlet! w:my_config_winid
    let buf = nvim_create_buf(v:false, v:true)
    let s:f_win =  nvim_open_win(buf, v:true, fwin_config)
  endif

  execute 'edit' file_path
  call cursor(row, col)
  call nvim_buf_clear_namespace(0, 0, 0, -1)
  let f_hi = nvim_buf_add_highlight(0, 0, 'Cursor', row-1, col-1,
        \ col-1+len(expand('<cword>')))
  setlocal nomodified
  execute 'normal! zz'
  execute 'wincmd P'
  let w:hi = f_hi
  let w:my_config_winid=s:f_win
endfunction

function! s:my_ale_close_ref() abort
  if exists('w:my_config_winid') && win_id2win(w:my_config_winid)
    autocmd! ale_ref
    call nvim_buf_clear_namespace(winbufnr(win_id2win(w:my_config_winid)), w:hi, 0, -1)
    call nvim_win_close(w:my_config_winid,1)
    unlet w:my_config_winid
  else
    unlet! w:my_config_winid
    execute 'q!'
  endif
endfunction

" settings for ALEHover---------------------------------
augroup ale_hover
  autocmd!
  autocmd FileType ale-preview.message :call s:ale_my_hover_config()
augroup END
function! s:ale_my_hover_config() abort
  let config = {
        \'relative':'cursor',
        \'width':60,
        \'height':15,
        \'col':0,
        \'row':1,
        \'style':'minimal'
        \}
  execute 'wincmd P'
  let win_hover = win_getid()
  call nvim_win_set_config(win_hover, config)
  execute 'wincmd w'
  call nvim_win_set_config(win_hover, config)
  nnoremap <buffer><silent> q :q
endfunction
