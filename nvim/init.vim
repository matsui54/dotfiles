let s:dein_dir = expand('~/.cache/dein')
let s:toml_dir = expand('~/.config/nvim')

if &runtimepath !~ '/dein.vim'
  if !isdirectory(s:dein_dir)
    execute '!git clone https://github.com/Shougo/dein.vim' s:dein_dir
  endif
	execute 'set runtimepath+=' . expand('~/.cache/dein/repos/github.com/Shougo/dein.vim')
endif

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

set number
set title
set tabstop=2
set shiftwidth=2
set smartindent
set clipboard=unnamedplus
set splitright
set showmatch


colorscheme molokai
set background=dark

inoremap <silent> jj <ESC>
nnoremap <silent> <Up> :wincmd k<CR>
nnoremap <silent> <Down> :wincmd j<CR>
nnoremap <silent> <Right> :wincmd l<CR>
nnoremap <silent> <Left> :wincmd h<CR>


augroup vimrc 
    autocmd!
		autocmd VimEnter * NoMatchParen
    autocmd User LanguageClientStarted setlocal signcolumn=yes
    autocmd User LanguageClientStopped setlocal signcolumn=auto
augroup END
