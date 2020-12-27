inoremap jj <Esc>

" add bracket automatically
inoremap <silent><expr> <CR> <SID>smart_bracket()
function! s:smart_bracket()
  let char = getline('.')[col('.') - 2]
  let brackets = {'{':'}', '(':')', '[':']', '<':'>'}
  let c_bracket = get(brackets, char, '')
  let ope = ''
  if c_bracket !=# ''
    if searchpair(char, '', c_bracket, 'n') != line('.')
      if getline('.')[col('.') -1] !=# c_bracket
        let ope = "\<End>" . c_bracket . "\<Esc>%a"
      endif
      let ope .= "\<CR>\<Esc>\<S-o>"
    else
      let ope = "\<CR>"
    endif
  else
    let ope = "\<CR>"
  endif
  return ope
endfunction

inoremap <silent> <C-r> <cmd>call show_register#show()<CR><C-r>

if has('nvim')
  tnoremap <A-h> <C-\><C-N><C-w>h
  tnoremap <A-j> <C-\><C-N><C-w>j
  tnoremap <A-k> <C-\><C-N><C-w>k
  tnoremap <A-l> <C-\><C-N><C-w>l
  tnoremap <Esc> <C-\><C-N>
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

nnoremap <silent><Leader>d :call <SID>run()<CR>

function! s:run() abort
  let cmd_table = {}
  let cmd_table.vim = 'w | source %'
  let cmd_table.cpp = 'wa | wincmd t | call My_quickrun_redirect()'
  let cmd_table.lua = 'w | luafile %'
  let cmd = get(cmd_table, &filetype, ':w | QuickRun')
  execute cmd
endfunction

nnoremap <A-h> <C-w>h
nnoremap <A-j> <C-w>j
nnoremap <A-k> <C-w>k
nnoremap <A-l> <C-w>l

" resize window using arrow key
nnoremap <expr><silent> <Up> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd -<CR>" : ":wincmd +<CR>"
nnoremap <expr><silent> <Down> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd +<CR>" : ":wincmd -<CR>"
nnoremap <expr><silent> <Right> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd ><CR>" : ":wincmd <<CR>"
nnoremap <expr><silent> <Left> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd <<CR>" : ":wincmd ><CR>"

nnoremap <expr><silent> <S-Up> (win_screenpos(win_getid())[0] < 3) ?
      \":5wincmd -<CR>" : ":5wincmd +<CR>"
nnoremap <expr><silent> <S-Down> (win_screenpos(win_getid())[0] < 3) ?
      \":5wincmd +<CR>" : ":5wincmd -<CR>"
nnoremap <expr><silent> <S-Right> (win_screenpos(win_getid())[1] < 3) ?
      \":10wincmd ><CR>" : ":10wincmd <<CR>"
nnoremap <expr><silent> <S-Left> (win_screenpos(win_getid())[1] < 3) ?
      \":10wincmd <<CR>" : ":10wincmd ><CR>"

nnoremap ; :
xnoremap ; :

" move around tabpages
nnoremap <C-j> gT
nnoremap <C-k> gt
nnoremap <Space><C-j> :tabmove -<CR>
nnoremap <Space><C-k> :tabmove +<CR>
nnoremap <Space>t :tabe<CR>

" stop highlighting for search
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>

" improved G
nnoremap G Gzz7<C-y>

"change local directory
nnoremap <Leader>cd :lcd %:h<CR>

" viml formatting
function! s:format_viml()
  let tmp = winsaveview()
  normal! ggVG=
  call winrestview(tmp)
endfunction
nnoremap <silent> <Leader>f :call <SID>format_viml()<CR>

" improved gd
nnoremap gd :call godef#go_to_definition()<CR>

" multiple search
nnoremap <expr> <Space>/ multi_search#hl_last_match() . "/"
nnoremap <expr> <Space>* multi_search#hl_last_match() . "*"
nmap <expr> <Space>l "\<C-l>" . multi_search#delete_search_all()

nmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
nmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>
vmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
vmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>

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

cnoremap <C-a> <Home>
cnoremap <C-e> <End>
cnoremap <C-n> <Down>
cnoremap <C-p> <Up>
cnoremap <C-y> <C-r>*

if has('unix')
  cnoremap <silent><expr> <C-Space> system('fcitx-remote -c')
endif

" commands
command! DeinClean :call map(dein#check_clean(), "delete(v:val, 'rf')") |
      \ call dein#recache_runtimepath()

command! -range=% Typing :call typing#start(<line1>, <line2>, 1)

command! LineCount :call line_counter#count()

command! -nargs=1 -complete=customlist,s:find_sessions
      \ SaveSession :call <SID>save_session(<f-args>)

function! s:find_sessions(...) abort
  let candidates = []
  for f in split(glob('~/.vim/sessions/*'), '\n')
    call add(candidates, fnamemodify(f, ':t:r'))
  endfor
  return candidates
endfunction
function! s:save_session(arg) abort
  wall
  let name = substitute(a:arg, ' ', '_', 'g') . '.vim'
  let path = expand('~/.vim/sessions/') . name
  if filereadable(path)
    let choice = confirm(printf('%s already exists. Overwrite?', path),
          \"&Overwrite\n&Cancel")
    if choice == 2
      return
    endif
  endif
  execute 'mksession!' . path
endfunction
