let s:clr_idx = 0
highlight Search2 ctermfg=234 ctermbg=203 guifg=#161821 guibg=#e27878
highlight Search3 ctermfg=234 ctermbg=203 guifg=#161821 guibg=#32cd32
highlight Search4 ctermfg=234 ctermbg=203 guifg=#161821 guibg=#1e90ff
let s:HI_LIST = ['Search2', 'Search3', 'Search4']

function! multi_search#hl_last_match()
  if s:clr_idx == len(s:HI_LIST)
    let s:clr_idx = 0
  endif
  if len(get(w:, 'multi_search_hl_idx', {})) >= len(s:HI_LIST)
    call s:multi_match_delete(s:clr_idx)
  endif
  call s:multi_match_add()
  let s:clr_idx +=1
  redraw
endfunction

function! multi_search#delete_search_all()
  if !exists('w:multi_search_hl_idx')
    return
  endif
  for idx in keys(w:multi_search_hl_idx)
    call s:multi_match_delete(idx)
  endfor
  let s:clr_idx = 0
endfunction

function! s:multi_match_delete(idx)
  let current_id = win_getid()
  for win in gettabinfo(tabpagenr())[0].windows
    call win_gotoid(win)
    call matchdelete(w:multi_search_hl_idx[a:idx])
    call remove(w:multi_search_hl_idx, a:idx)
  endfor
  call win_gotoid(current_id)
endfunction
function! s:multi_match_add()
  let current_id = win_getid()
  for win in gettabinfo(tabpagenr())[0].windows
    call win_gotoid(win)
    if !exists('w:multi_search_hl_idx')
      let w:multi_search_hl_idx = {}
    endif
    let w:multi_search_hl_idx[s:clr_idx] = s:search_and_hi()
  endfor
  call win_gotoid(current_id)
endfunction

function! s:search_and_hi()
  let word = getreg('/')
  if &ignorecase && match(word, '\\C') == -1 &&
        \!(&smartcase && word !~# tolower(word))
    let word .= '\\c'
  endif
  return matchadd(s:HI_LIST[s:clr_idx], word)
endfunction
