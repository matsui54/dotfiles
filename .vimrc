"dein Scripts-----------------------------
if &compatible
  set nocompatible               " Be iMproved
endif

" Required:
set runtimepath+=/home/haruki/.vim/bundles/repos/github.com/Shougo/dein.vim

" Required:
if dein#load_state('/home/haruki/.vim/bundles')
  call dein#begin('/home/haruki/.vim/bundles')

  " Let dein manage dein
  " Required:
  call dein#add('/home/haruki/.vim/bundles/repos/github.com/Shougo/dein.vim')

  " Add or remove your plugins here like this:
  "call dein#add('Shougo/neosnippet.vim')
  "call dein#add('Shougo/neosnippet-snippets')
  call dein#add('sheerun/vim-polyglot')
  call dein#add('vim-scripts/SingleCompile')
  

  " Required:
  call dein#end()
  call dein#save_state()
endif

" Required:
filetype plugin indent on
syntax enable

" If you want to install not installed plugins on startup.
if dein#check_install()
  call dein#install()
endif

"End dein Scripts-------------------------

set number
set title
set tabstop=4
set shiftwidth=4
set smartindent
set clipboard=unnamedplus

nmap <F9> :SCCompile<cr>
nmap <F5> :SCCompileRun<cr>
