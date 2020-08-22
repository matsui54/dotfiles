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
      let ope = "\<End>" . c_bracket . "\<ESC>%a"
    endif
    let ope .= "\<CR>\<ESC>\<S-o>"
  else
    let ope = "\<CR>"
  endif
  return ope
endfunction

inoremap <C-r> <ESC>:call show_register#show()<CR>a<C-r>

if has('nvim')
  nnoremap <expr> <leader>d (&filetype=='vim') ? ":w <bar> :source %<CR>" :
        \ (&filetype=='python') ? ":w <bar> :QuickRun <CR>" :
        \ ":wa <bar> :wincmd t <bar> :QuickRun <in.txt <CR>"
  tnoremap <C-\><C-\> <C-\><C-n>
  command! Fterm :call <SID>floating_terminal()
  command! Vterm :vsplit | :terminal
  command! Tterm :tabnew | :terminal
endif

function! s:floating_terminal() abort
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
  nnoremap <buffer> q :q<CR>
endfunction

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

" multiple search
nnoremap <expr> <Space>/ multi_search#hl_last_match() . "/"
nnoremap <expr> <Space>* multi_search#hl_last_match() . "*"
nmap <expr> <Space>l "\<C-l>" . multi_search#delete_search_all()

" from nelstrom/vim-visual-star-search
function! s:VSetSearch(cmdtype)
  let temp = @s
  norm! gv"sy
  let @/ = '\V' . substitute(escape(@s, a:cmdtype.'\'), '\n', '\\n', 'g')
  let @s = temp
endfunction

xnoremap * :<C-u>call <SID>VSetSearch('/')<CR>/<C-R>=@/<CR><CR>
xnoremap # :<C-u>call <SID>VSetSearch('?')<CR>?<C-R>=@/<CR><CR>

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
    execute "normal! \<C-c>"
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

command! -nargs=1 SaveSession :call <SID>save_session(<f-args>)

function! s:save_session(arg) abort
  wall
  let name = substitute(a:arg, " ", "_", "g") . ".vim"
  let path = expand("~/.vim/sessions/") . name
  if filereadable(path)
    let choice = confirm(printf("%s already exists. Overwrite?", path), 
          \"&Overwrite\n&Cancel")
    if choice == 2
      return
    endif
  endif
  execute "mksession!" . path 
endfunction
