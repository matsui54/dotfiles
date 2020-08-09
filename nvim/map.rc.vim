inoremap jj <ESC>

" add bracket automatically
inoremap <silent><expr> <CR> <SID>smart_bracket()
function! s:smart_bracket()
  let char = getline('.')[col('.') - 2]
  let brackets = {'{':'}', '(':')', '[':']', '<':'>'}
  let c_bracket = get(brackets, char, '')
  let ope = ''
  if c_bracket != ''
    if searchpair(char, '', c_bracket, 'n') != line('.')
      let ope = "\<End>" . c_bracket . "\<ESC>T" . char . "i"
    endif
    let ope .= "\<CR>\<ESC>\<S-o>"
  else
    let ope = "\<CR>"
  endif
  return ope
endfunction

if has('nvim')
  nnoremap <expr> <leader>d (&filetype=='vim') ? ":w <bar> :source %<CR>" :
        \ (&filetype=='python') ? ":w <bar> :QuickRun <CR>" :
        \ ":wa <bar> :wincmd t <bar> :QuickRun <in.txt <CR>"
  tnoremap <C-\><C-\> <C-\><C-n>
endif

nnoremap <Leader>m :wa <Bar> :make<CR>

" resize window using arrow key
nnoremap <expr><silent> <Up> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd -<CR>" : ":wincmd +<CR>"
nnoremap <expr><silent> <Down> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd +<CR>" : ":wincmd -<CR>"
nnoremap <expr><silent> <Right> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd ><CR>" : ":wincmd <<CR>"
nnoremap <expr><silent> <Left> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd <<CR>" : ":wincmd ><CR>"

nnoremap ; :
xnoremap ; :

" move around tabpages
nnoremap <C-j> gT
nnoremap <C-k> gt

" erase highlight for search
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>

" improved G
nnoremap G Gzz7<C-y>

"change local directory
nnoremap <Leader>cd :lcd %:h<CR>

nnoremap j gj
nnoremap k gk
xnoremap j gj
xnoremap k gk

" for repeating indentation
xnoremap <silent> > >:call <SID>improved_indent()<CR>gv
xnoremap <silent> < <:call <SID>improved_indent()<CR>gv
function! s:improved_indent()
  augroup my_indent
    autocmd cursormoved * call s:exit_indent_mode()
  augroup END
  let s:moved = v:false
endfunction
function! s:exit_indent_mode()
  if s:moved
    if mode() == 'V'
      normal! V
    endif
    autocmd! my_indent
    let s:moved = v:false
  else
    let s:moved = v:true
  endif
endfunction

" insert parent directory of current file
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'

" Command-line mode keymappings:
" <C-a>, A: move to head.
cnoremap <C-a>          <Home>
" <C-d>: delete char.
cnoremap <C-d>          <Del>
" <C-e>, E: move to end.
cnoremap <C-e>          <End>
" <C-n>: next history.
cnoremap <C-n>          <Down>
" <C-p>: previous history.
cnoremap <C-p>          <Up>
" <C-y>: paste.
cnoremap <C-y>          <C-r>*
" <C-g>: Exit.
cnoremap <C-g>          <C-c>

if has('unix')
  cnoremap <silent><expr> <C-Space> system('fcitx-remote -c')
endif
