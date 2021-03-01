augroup MyAutoCmd
  autocmd!
augroup END

" dein settings--------------------------------------------
let g:dein#lazy_rplugins = v:true

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

if has('vim_starting') && !empty(argv())
  call vimrc#on_filetype()
endif

if filereadable(expand('~/.config/secret.vim'))
  source ~/.config/secret.vim
endif

if vimrc#is_windows()
  let g:python3_host_prog = 'C:\Users\harum\AppData\Local\Programs\Python\Python38\python.EXE'
  set shell=C:\Windows\System32\cmd.exe
else
  " use virtualenv
  let s:py3_dir = expand('~/.vim/python3/')
  let g:python3_host_prog = s:py3_dir . 'bin/python3'
  let $PATH = s:py3_dir . 'bin:' . $PATH
endif

source ~/dotfiles/nvim/map.rc.vim

source ~/dotfiles/nvim/options.rc.vim

let g:loaded_2html_plugin      = 1
let g:loaded_logiPat           = 1
let g:loaded_getscriptPlugin   = 1
let g:loaded_gzip              = 1
let g:loaded_man               = 1
let g:loaded_matchit           = 1
let g:loaded_netrwFileHandlers = 1
let g:loaded_netrwPlugin       = 1
let g:loaded_netrwSettings     = 1
let g:loaded_rrhelper          = 1
let g:loaded_shada_plugin      = 1
let g:loaded_spellfile_plugin  = 1
let g:loaded_tarPlugin         = 1
let g:loaded_tutor_mode_plugin = 1
let g:loaded_vimballPlugin     = 1
let g:loaded_zipPlugin         = 1
