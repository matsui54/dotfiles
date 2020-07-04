filetype plugin indent on
syntax enable

set number
set title
set expandtab
set tabstop=2
set shiftwidth=0
set smartindent
set clipboard=unnamedplus
set splitright
set showmatch
set showtabline=2
set termguicolors
set smartcase
set ignorecase
set completeopt-=preview

if has('nvim')
  colorscheme hybrid
  highlight clear MatchParen
  highlight MatchParen cterm=underline, gui=underline
  command! Fterminal :call Floating_terminal()
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

if has('unix')
  augroup im_change
    autocmd!
    autocmd InsertEnter * :call system('fcitx-remote -c')
    autocmd InsertLeave * :call system('fcitx-remote -o')
    autocmd VimEnter * :call system('fcitx-remote -o')
    autocmd VimLeave * :call system('fcitx-remote -c')
    autocmd CmdlineLeave * :call system('fcitx-remote -o')
    autocmd CompleteChanged * :call system('fcitx-remote -c')
  augroup END

  " let g:fcitx_status = 'en'
endif

" function! s:save_fcitx_status()
"   if system('fcitx-remote') == 1
"     let g:fcitx_status = 'ja'
"   else
"     let g:fcitx_status = 'en'
"   endif
"   call system('fcitx-remote -o')
" endfunction

" function! s:resume_ime()
"   if g:fcitx_status ==# 'ja'
"     call system('fcitx-remote -c')
"   else
"     call system('fcitx-remote -o')
"   endif
" endfunction

" netrw settings------------------------------------------
let g:netrw_preview=1

autocmd FileType netrw call s:netrw_my_settings()

function! s:netrw_my_settings()
  nmap l <CR>
  nmap h -
endfunction

" tabline settings----------------------------------------
set tabline=%!MyTabLine()

function MyTabLine()
  let s = ''
  " the number of tabs
  let cnttab = tabpagenr('$')

  for i in range(cnttab)
    " tab number of current tab
    let currentnr = tabpagenr()

    highlight MyTabHi cterm=underline, gui=underline
    let hi = (i + 1 == currentnr) ? '%#airline_c#' : '%#MyTabHi#'

    let space1 = (i == currentnr) ? '  ' : ' '

    let bufnrs = tabpagebuflist(i+1)
    " shows the number of windows
    let bufno = len(bufnrs)
    if bufno < 2
      let bufno = ''
    endif
    " if the buffer is changed, show '+'
    let mod = len(filter(copy(bufnrs), 'getbufvar(v:val, "&modified")')) ? '+' : ''
    let space2 = (bufno . mod) ==# '' ? '' : ' '

    let s .= hi . space1 . bufno . mod . space2 . '%{MyTabLabel(' . (i + 1) . ')} '

    " if the tab is not current, add '|'.
    if i + 1 != cnttab && i + 1 != currentnr && i +2 != currentnr
      let s .= '|'
    elseif i + 2 == currentnr
      let s .= ' '
    endif
  endfor

  let s .= '%#MyTabHi#%T'

  "Show current directory
  let s .= '%=%#MyTabHi#'
  let s .= strftime('%H:%M')
  let s .= ' %#Cursor#%{fnamemodify(getcwd(), ":~/")}'

  return s
endfunction

function MyTabLabel(n)
  let buflist = tabpagebuflist(a:n)
  let winnr = tabpagewinnr(a:n)
  "don't show directory name
  let res = substitute(bufname(buflist[winnr - 1]), '.\+\/', '', '')
  if res ==# ''
    let res = '[]'
  endif
  return res
endfunction
