inoremap jj <Esc>

inoremap <silent> <C-r> <cmd>call show_register#show()<CR><C-r>

if has('nvim')
  tnoremap <A-h> <C-\><C-N><C-w>h
  tnoremap <A-j> <C-\><C-N><C-w>j
  tnoremap <A-k> <C-\><C-N><C-w>k
  tnoremap <A-l> <C-\><C-N><C-w>l
endif

nnoremap <Leader>m <cmd>wa <Bar> make<CR>

" nnoremap <silent><Leader>d <cmd>call <SID>run()<CR>
" function! s:run() abort
"   let cmd_table = {}
"   " let cmd_table.vim = 'w | source %'
"   let cmd_table.cpp = 'wa | wincmd t | call My_quickrun_redirect()'
"   let cmd_table.lua = 'w | luafile %'
"   let cmd_table.gnuplot = 'w | !gnuplot %'
"   let cmd = get(cmd_table, &filetype, 'w | QuickRun')
"   execute cmd
" endfunction

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
nnoremap <Space><C-j> <cmd>tabmove -<CR>
nnoremap <Space><C-k> <cmd>tabmove +<CR>
nnoremap <Space>t <cmd>tabe<CR>

" stop highlighting for search
nnoremap <silent> <C-l> <cmd>nohlsearch<CR><C-l>

" improved G
nnoremap G Gzz7<C-y>

"change local directory
nnoremap <Leader>cd <cmd>tcd %:h<CR>

" viml formatting
function! s:format_viml()
  let tmp = winsaveview()
  normal! ggVG=
  call winrestview(tmp)
endfunction
nnoremap <silent> <Leader>f <cmd>call <SID>format_viml()<CR>

" improved gd
nnoremap gd <cmd>call godef#go_to_definition()<CR>

" multiple search
nnoremap <expr> <Leader>/ multi_search#hl_last_match() . "/"
nnoremap <expr> <Leader>* multi_search#hl_last_match() . "*"
nmap <expr> <Leader>l "\<C-l>" . multi_search#delete_search_all()

nmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
nmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>
vmap <silent> <C-u> <cmd>call smooth_scroll#up()<CR>
vmap <silent> <C-d> <cmd>call smooth_scroll#down()<CR>

" from nelstrom/vim-visual-star-search
function! s:VSetSearch(cmdtype)
  let temp = @"
  norm! y
  let @/ = '\V' . substitute(escape(@", a:cmdtype.'\'), '\n', '\\n', 'g')
  let @" = temp
endfunction

xnoremap * <cmd>call <SID>VSetSearch('/')<CR>/<C-R>=@/<CR><CR>
xnoremap # <cmd>call <SID>VSetSearch('?')<CR>?<C-R>=@/<CR><CR>

nnoremap j gj
nnoremap k gk
xnoremap j gj
xnoremap k gk

" for repeating indentation
xnoremap <silent> > ><cmd>call <SID>improved_indent()<CR>gv
xnoremap <silent> < <<cmd>call <SID>improved_indent()<CR>gv
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
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:p:h').'/' : '%%'

cnoremap <C-a> <Home>
cnoremap <C-e> <End>
cnoremap <C-n> <Down>
cnoremap <C-p> <Up>
cnoremap <C-y> <C-r>*
cnoremap <C-f> <Right>
cnoremap <C-b> <Left>

" commands
command! DeinClean :call map(dein#check_clean(), "delete(v:val, 'rf')") |
      \ call dein#recache_runtimepath()

command! -range=% Typing :call typing#start(<line1>, <line2>, 1)

command! LineCount :call line_counter#count()

command! -nargs=1 -complete=customlist,s:find_sessions
      \ SaveSession :call <SID>save_session(<f-args>)

command! MyUpdateRemotePlugins :call s:update_rplugins()

function! s:update_rplugins() abort
  call dein#source(['defx.nvim', 'denite.nvim'])
  UpdateRemotePlugins
endfunction

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

" from https://zenn.dev/monaqa/articles/2020-09-17-vim-zenn-command
function! s:create_zenn_article(article_name) abort
  let date = strftime("%Y-%m-%d")
  let slug = date . "-" . a:article_name
  call system("npx zenn new:article --slug " . slug )
  let article_path = "articles/" . slug . ".md"
  execute "edit " . article_path
endfunction

command! -nargs=1 ZennCreateArticle call <SID>create_zenn_article("<args>")
