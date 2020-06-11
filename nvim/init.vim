" dein settings--------------------------------------------
let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim' 
let s:toml_dir = expand('~/.config/nvim')

if !isdirectory(s:dein_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath+=' . s:dein_repo_dir
set runtimepath+=~/OxfDictionary.nvim

" dein settings 
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)


  "Load TOML
  let s:toml = s:toml_dir . '/dein.toml'
  let s:lazy_toml = s:toml_dir . '/dein_lazy.toml'

  call dein#load_toml(s:toml, {'lazy': 0})
  call dein#load_toml(s:lazy_toml, {'lazy': 1})


  "finalize
  call dein#end()
  call dein#save_state()
endif

filetype plugin indent on
syntax enable

if dein#check_install()
  call dein#install()
endif

call map(dein#check_clean(), "delete(v:val, 'rf')")
call dein#recache_runtimepath()
" end dein settings---------------------------------------

let g:OxfDictionary#app_id='3fc46c58'
let g:OxfDictionary#app_key='c4603e15e4eb3f7219bd477823507ad6'
set runtimepath+=/home/haruki/work/OxfDictionary.nvim

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

colorscheme PaperColor
highlight Normal ctermbg=none
highlight LineNr ctermbg=none
highlight clear MatchParen
highlight MatchParen cterm=underline

source ~/.config/nvim/plugins/keymappings.vim

augroup vimrc 
  autocmd!
augroup END

if has('unix')
  augroup im_change
    autocmd InsertEnter * :call system('fcitx-remote -c')
    autocmd InsertLeave * :call system('fcitx-remote -o')
    autocmd VimEnter * :call system('fcitx-remote -o')
    autocmd VimLeave * :call system('fcitx-remote -c')
    autocmd CmdlineLeave * :call system('fcitx-remote -o')
  augroup END
endif


" netrw settings------------------------------------------
let g:netrw_preview=1

function! Netrw_map_space(islocal) abort
  return 'normal! <Space>'
endfunction

let g:Netrw_UserMaps = [['<Space>', 'Netrw_map_space']]


" tabline settings----------------------------------------
function MyTabLine()
  let s = ''
  " the number of tabs
  let cnttab = tabpagenr('$')

  for i in range(cnttab)
    " tab number of current tab
    let currentnr = tabpagenr()

    highlight MyTabHi cterm=underline, ctermbg=none
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
  let s .= '%=%#Cursor#%{fnamemodify(getcwd(), ":~/")}'

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

set tabline=%!MyTabLine()
