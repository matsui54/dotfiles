augroup MyAutoCmd
  autocmd!
  autocmd VimLeavePre,BufWrite * mksession! ~/.vim/sessions/saved_session.vim
augroup END

" dein settings--------------------------------------------
let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim' 
let s:toml_dir = expand('~/dotfiles/nvim')

if !isdirectory(s:dein_repo_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath+=' . s:dein_repo_dir

" dein settings 
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir)

  call dein#load_toml(s:toml_dir . '/dein.toml', {'lazy': 0})
  call dein#load_toml(s:toml_dir . '/dein_lazy.toml', {'lazy': 1})

  "finalize
  call dein#end()
  call dein#save_state()
endif

if dein#check_install()
  call dein#install()
endif

" end dein settings---------------------------------------

execute 'set runtimepath+=' . expand('~/work/OxfDictionary.nvim')
if filereadable(expand('~/.config/secret.vim'))
  source ~/.config/secret.vim
endif

if has('win32') || has('win64')
  let g:python3_host_prog = 'C:\Users\harum\AppData\Local\Programs\Python\Python38\python.EXE'
endif

source ~/dotfiles/nvim/map.rc.vim

source ~/dotfiles/nvim/options.rc.vim
