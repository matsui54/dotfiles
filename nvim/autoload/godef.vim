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
  if search('\c<sid>\k*\%#', 'n')
    return 's:'
  endif

  let &l:iskeyword = keyword
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
    if filereadable(path)
      execute 'e ' . path
      call search('^\s*fun\%[ction]\%[!]\s*\zs' . a:name)
      return
    endif
  endif

  for rtp in split(&runtimepath, ',')
    let path = rtp . '/autoload/' . tailpath
    if filereadable(path)
      execute 'e ' . path
      call search('^\s*fun\%[ction]\%[!]\s*\zs' . a:name)
      return
    endif
  endfor
endfunction

function! s:jump_to_local_func(name) abort
  call search('^\s*fun\%[ction]\%[!]\s*\zs' . a:name)
endfunction

function! s:jump_to_var(name) abort
  if a:name =~# '^[gsbwt]:'
    call cursor(1, 1)
    call search('\<let\s\+\zs' . a:name)
  elseif a:name =~# '^a:'
    call search('^\s*fu\%[nction]!\?\s\+[^(]\+(\zs', 'b')
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
    call cursor(pos)
  endif
endfunction
