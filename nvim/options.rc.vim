filetype plugin indent on
syntax enable

set number
set title

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

set clipboard=unnamedplus

set smartcase
set ignorecase

set showmatch
" Highlight <>.
set matchpairs+=<:>

" Set undofile.
set undofile

set termguicolors

set completeopt-=preview

set splitright

if exists('&inccommand')
  set inccommand=nosplit
endif

if exists('&pumblend')
  set pumblend=30
endif

if exists('&winblend')
  set winblend=30
endif

if has('nvim')
  colorscheme iceberg
  highlight clear MatchParen
  highlight MatchParen cterm=underline, gui=underline
  command! Fterm :call Floating_terminal()
  command! Vterm :vsplit | :terminal
  command! Tterm :tabnew | :terminal
endif

function! Floating_terminal() abort
  call nvim_open_win(
        \ nvim_create_buf(v:false, v:true), 1,
        \ {'relative':'win',
        \ 'width':100,
        \ 'height':28,
        \ 'col':20,
        \ 'row':3}
        \ )
  terminal
  hi MyFWin ctermbg=0, guibg=#000000 " cterm:Black, gui:DarkBlue
  call nvim_win_set_option(0, 'winhl', 'Normal:MyFWin')
  setlocal nonumber
  setlocal winblend=15
endfunction

function! s:is_wsl()
  return executable('cmd.exe')
endfunction

if has('unix') && !s:is_wsl()
  augroup im_change
    autocmd!
    autocmd InsertEnter * :call system('fcitx-remote -c')
    autocmd InsertLeave * :call system('fcitx-remote -o')
    autocmd VimEnter * :call system('fcitx-remote -o')
    autocmd VimLeave * :call system('fcitx-remote -c')
    autocmd CmdlineLeave * :call system('fcitx-remote -o')
    autocmd CompleteChanged * :call system('fcitx-remote -c')
  augroup END
endif

" netrw settings------------------------------------------
let g:netrw_preview=1

autocmd FileType netrw call s:netrw_my_settings()

function! s:netrw_my_settings()
  nmap <buffer>l <CR>
  nmap <buffer>h -
endfunction

" tabline settings----------------------------------------
set showtabline=2
set tabline=%!MyTabLine()

function MyTabLine()
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
  let dir = fnamemodify(getcwd(), ":~/")
  let len_tail = strlen(time . dir) + 3

  " shrink tabs to fit to screen
  if len_str + len_tail > screen_width
    let capacity = screen_width - len_tail
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
  let tab.name = MyTabLabel(n + 1)
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

function MyTabLabel(n)
  let buflist = tabpagebuflist(a:n)
  let winnr = tabpagewinnr(a:n)
  " show only file name
  let res = substitute(bufname(buflist[winnr - 1]), '\v.+(\\|\/)', '', '')
  if res ==# ''
    let res = '[]'
  endif
  return res
endfunction
