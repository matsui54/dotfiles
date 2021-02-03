function! browser_search#show_prompt() abort
  let buf = nvim_create_buf(v:false, v:true)
  let width = float2nr(winwidth(0) * 0.8)
  let opts = {
        \'relative': 'editor',
        \'width': width,
        \'height': 1,
        \'col': (winwidth(0) - width)/2,
        \'row': 5,
        \'anchor': 'NW',
        \}
  let win = nvim_open_win(buf, 1, opts)
  set filetype=google
  inoremap <buffer><CR> <ESC><cmd>call <SID>search()<CR>
  nnoremap <buffer><CR> <cmd>call <SID>search()<CR>
  nnoremap <buffer>q :q<CR>
  startinsert
endfunction

function! s:search() abort
  let line = getline(1)
  :q
  if line != ''
    execute 'OpenBrowserSearch ' . line
  endif
endfunction
