function! godef#go_to_definition() abort
  let cur_word = expand('<cword>')
  let prefix = s:get_prefix()
  let is_dict_value = search('\.\k*\%#', 'n')
  if is_dict_value
    let cur_word = s:get_dict_func()
  endif

  if s:is_func()
    if cur_word =~# '#'
      call s:jump_to_autoload_func(prefix . cur_word)
    else
      call s:jump_to_local_func(prefix . cur_word)
    endif
  else
    let cur_word = substitute(s:get_dict_func(), '\.[^\.]\+', '', 'g')
    call s:jump_to_var(prefix . cur_word)
  endif
endfunction

function! s:get_dict_func() abort
  let keyword = &iskeyword
  setlocal iskeyword=@,48-57,_,192-255,#,.
  let word = expand('<cword>')
  let &l:iskeyword = keyword
  return word
endfunction

function! s:get_prefix() abort
  let keyword = &iskeyword
  setlocal iskeyword=@,48-57,_,192-255,#,.,:

  let word = expand('<cword>')
  let &l:iskeyword = keyword
  if search('\c<sid>\k*\%#', 'n')
    return 's:'
  endif

  if word =~# '^[gswbta]:'
    return word[0] . ':'
  else
    return ''
  endif
endfunction

function! s:is_func() abort
  return search('\%#\k*(', 'n')
endfunction

function! s:get_dict_root() abort
  let keyword = &iskeyword
  setlocal iskeyword+=.
  let word = expand('<cword>')
  let &l:iskeyword = keyword
  return word
endfunction

function! s:jump_to_autoload_func(name) abort
  let sfile = expand('%:p')
  let tailpath = substitute(
        \ substitute(a:name, '#', '/', 'g'), '\/[^\/]*$', '.vim', '')
  if sfile =~# '/autoload/'
    let project_root = substitute(sfile, 'autoload\zs.*', '', '')
    let path = project_root . '/' . tailpath
    call s:jump_to_def(path, '^\s*fun\%[ction]\%[!]\s*\zs' . a:name)
  endif

  for rtp in split(&runtimepath, ',')
    let path = rtp . '/autoload/' . tailpath
    call s:jump_to_def(path, '^\s*fun\%[ction]\%[!]\s*\zs' . a:name)
  endfor
endfunction

function! s:jump_to_local_func(name) abort
  call s:search('^\s*fun\%[ction]\%[!]\s*\zs' . a:name, '')
endfunction

function! s:jump_to_var(name) abort
  if a:name =~# '^[gsbwt]:'
    let tmp = winsaveview()
    call cursor(1, 1)
    if s:search('\<let\s\+\zs' . a:name, '') == 1
      call winrestview(tmp)
    endif
  elseif a:name =~# '^a:'
    call s:search('^\s*fu\%[nction]!\?\s\+[^(]\+(\zs', 'b')
  else
    let line_num = line('.')
    let pos = [0, 0]
    while line_num > 0
      let line = getline(line_num)
      if line =~# '^\s*endfu\%[nction]\>'
        let pos = [0, 0]
        break
      elseif line =~# '^\s*fu\%[nction]!\?\s\+'
        break
      elseif line =~# '^\s*\%(let\|for\)\s\+' . a:name . '\>'
        let pos = [line_num, match(line, a:name) + 1]
        if line =~# '^\s*for'
          break
        endif
      endif
      let line_num -= 1
    endwhile
    if pos[0] != 0
      normal! m'
      call cursor(pos)
    endif
  endif
endfunction

function! s:jump_to_def(path, pattern) abort
  if !filereadable(a:path)
    return 1
  endif
  if a:path ==# expand('%')
    let tmp = winsaveview()
    if searchpos(a:pattern)[0] == 0
      call winrestview(tmp)
      return 1
    endif
    return 0
  endif
  let listed = buflisted(a:path)
  execute 'e ' . a:path
  if searchpos(a:pattern)[0] == 0
    let bname = bufname()
    execute "normal \<C-o>"
    if !listed
      execute 'bdelete! ' . bname
    endif
    return 1
  endif
  return 0
endfunction

function! s:search(pattern, flag) abort
  let pos = searchpos(a:pattern, 'n' . a:flag)
  if pos[0] != 0
    normal! m'
    call cursor(pos)
    return 0
  endif
  return 1
endfunction
