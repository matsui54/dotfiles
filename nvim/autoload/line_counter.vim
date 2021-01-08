function! line_counter#count() abort
  let rc_root = expand('~/dotfiles/nvim')
  let s:cnt_line = 0
  let s:result = []

  call s:glob(rc_root)

  call sort(s:result, function('s:comp'))
  for r in s:result
    echo r.fname r.lines
  endfor
  echo s:cnt_line
endfunction

function! s:measure(fname)
  let lines = readfile(a:fname)
  let pat = '^\s*$\|^\s*["#\\]'
  return len(filter(lines, 'v:val !~ pat'))
endfunction

function! s:comp(v1, v2) abort
  return a:v2.lines - a:v1.lines
endfunction

function! s:glob(path) abort
  for f in split(glob(a:path . '/*'), '\n')
    if isdirectory(f) && fnamemodify(f, ':t') !=# 'not_used'
      call s:glob(f)
    elseif index(['vim', 'py', 'snippets', 'toml', 'lua'],
          \ fnamemodify(f, ':e')) >= 0
      let fname = fnamemodify(f, ':p')
      call add(s:result, {'fname':fname, 'lines':s:measure(f)})
      let s:cnt_line += s:measure(f)
    endif
  endfor
endfunction
