inoremap jj <ESC>

" add bracket automatically
inoremap <silent><expr> <CR> <SID>check_bracket()
function! s:check_bracket()
  let col = col('.') - 1
  let char = getline('.')[col - 1]
  let brackets = {'{':'}', '(':')', '[':']'}
  let ope=''
  if get(brackets, char, '') != ''
    let ope = brackets[char] . "\<Left>\<CR>\<ESC>\<S-o>"
  else
    let ope = "\<CR>"
  endif
  return ope
endfunction

nnoremap <expr> <leader>d (&filetype=='vim') ? ":w <bar> :source %<CR>" :
      \ (&filetype=='python') ? ":QuickRun <CR>" :
      \ ":wa <bar> :wincmd t <bar> :QuickRun <in.txt <CR>"
nnoremap <expr><silent> <Up> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd -<CR>" : ":wincmd +<CR>"
nnoremap <expr><silent> <Down> (win_screenpos(win_getid())[0] < 3) ?
      \":wincmd +<CR>" : ":wincmd -<CR>"
nnoremap <expr><silent> <Right> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd ><CR>" : ":wincmd <<CR>"
nnoremap <expr><silent> <Left> (win_screenpos(win_getid())[1] < 3) ?
      \":wincmd <<CR>" : ":wincmd ><CR>"
nnoremap ; :
nnoremap <C-j> gT
nnoremap <C-k> gt
nnoremap <silent> <C-l> :<C-u>nohlsearch<CR><C-l>
nnoremap G Gzz7<C-y>
"change local directory
nnoremap <Leader>cd :lcd %:h<CR>
nnoremap j gj
nnoremap k gk

cnoremap <silent><expr> <C-Space> system('fcitx-remote -c')
cnoremap <expr> %% getcmdtype() == ':' ? expand('%:h').'/' : '%%'
