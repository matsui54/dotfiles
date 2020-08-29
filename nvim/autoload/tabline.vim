function tabline#MyTabLine()
  let num_tab = tabpagenr('$')
  let screen_width = &columns
  let len_str = 0
  let tabs = {}
  highlight MyTabHi cterm=underline, gui=underline

  for i in range(num_tab)
    let tabs[i] = s:get_tab_info(i, num_tab)
    let len_str += tabs[i].len
  endfor

  "Show time and current directory
  let time = strftime('%H:%M')
  let dir = fnamemodify(getcwd(), ':~/')
  let len_tail = strlen(time . dir) + 3

  " shrink tabs to fit to screen
  if len_str + len_tail > screen_width
    let dir = substitute(dir, '\/[^\/]\{3}\zs[^\/]\+', '…', 'g')
    let capacity = screen_width - strlen(time . dir) - 3
    if capacity < len_str
      let avr = capacity / num_tab
      for i in range(num_tab)
        if tabs[i].len < avr
          let capacity += avr - tabs[i].len
        endif
      endfor

      let avr = capacity / num_tab - 1
      for i in range(num_tab)
        if tabs[i].len > avr
          let len = avr - len(tabs[i].pre . tabs[i].post) - 1
          let tabs[i].name = tabs[i].name[:len] . '…'
        endif
      endfor
    endif
  endif

  let s = ''
  for i in range(num_tab)
    let tab = tabs[i]
    let s .= tab.hi . tab.pre . tab.name . tab.post
  endfor
  let s .= '%#MyTabHi#%T%=%#MyTabHi#' . time . ' %#Cursor#' . dir
  return s
endfunction

function! s:get_tab_info(i, num_tab)
  let n = a:i
  let tab = {}
  " tab number of current tab
  let current_tab_nr = tabpagenr()

  let tab.hi = (n + 1 == current_tab_nr) ? '%#TabLineSel#' : '%#MyTabHi#'

  let space1 = (n == current_tab_nr) ? '  ' : ' '

  let bufnrs = tabpagebuflist(n+1)
  " shows the number of windows
  let bufno = len(bufnrs)
  if bufno < 2
    let bufno = ''
  endif
  " if the buffer is changed, show '+'
  let mod = len(filter(copy(bufnrs), 'getbufvar(v:val, "&modified")')) ? '+' : ''
  let space2 = (bufno . mod) ==# '' ? '' : ' '

  let tab.pre = space1 . bufno . mod . space2
  let tab.name = s:myTabLabel(n + 1)
  let tab.post = ' '

  " if the tab is not current, add '|'.
  if n + 1 != a:num_tab && n + 1 != current_tab_nr && n +2 != current_tab_nr
    let tab.post .= '|'
  elseif n + 2 == current_tab_nr
    let tab.post .= ' '
  endif

  let tab.len = strlen(tab.pre . tab.name . tab.post)
  return tab
endfunction

function s:myTabLabel(n)
  let buflist = tabpagebuflist(a:n)
  let winnr = tabpagewinnr(a:n)
  " show only file name
  let res = substitute(bufname(buflist[winnr - 1]), '\v.+(\\|\/)', '', '')
  if res ==# ''
    let res = '[]'
  endif
  return res
endfunction

