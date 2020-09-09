function! line_counter#count() abort
  let rc_root = expand('~/dotfiles/nvim')
  let s:cnt_line = 0
  call s:glob(rc_root)
  echo s:cnt_line
endfunction

function! s:measure(fname)
  let lines = readfile(a:fname)
  let pat = '^\s*$\|^\s*["#\\]'
  return len(filter(lines, 'v:val !~ pat'))
endfunction

function! s:glob(path) abort
  for f in split(glob(a:path . '/*'), '\n')
    if isdirectory(f) && fnamemodify(f, ':t') !=# 'not_used'
      call s:glob(f)
    elseif index(['vim', 'py', 'snippets', 'toml'],
          \ fnamemodify(f, ':e')) >= 0
      echo fnamemodify(f, ':p:.') . ' ' . s:measure(f)
      let s:cnt_line += s:measure(f)
    endif
  endfor
endfunction
