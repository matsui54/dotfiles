augroup MyAutoCmd
  autocmd!
augroup END

" dein settings--------------------------------------------
let g:dein#lazy_rplugins = v:true
let g:dein#auto_recache = !has('win32')
let g:dein#install_progress_type = 'floating'
if !vimrc#is_windows()
  let g:dein#types#git#default_protocol = 'ssh'
endif
let g:dein#install_check_diff = v:true

let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'
let s:toml_dir = expand('~/dotfiles/nvim')

let s:dein_toml = s:toml_dir . 'dein.toml'
let s:dein_lazy_toml = s:toml_dir . 'dein_lazy.toml'
let s:dein_ddc_toml = s:toml_dir . 'ddc.toml'
let s:dein_ddu_toml = s:toml_dir . 'ddu.toml'
let s:dein_ft_toml = s:toml_dir . 'dein_ft.toml'

if !isdirectory(s:dein_repo_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath+=' . s:dein_repo_dir

" dein settings
if dein#load_state(s:dein_dir)
  call dein#begin(s:dein_dir, [
        \ expand('<sfile>'), s:dein_toml, s:dein_lazy_toml, s:dein_ft_toml,
        \ s:dein_ddc_toml, s:dein_ddu_toml,
        \ ])
  call dein#load_toml(s:toml_dir . '/dein.toml', {'lazy': 0})
  call dein#load_toml(s:toml_dir . '/dein_lazy.toml', {'lazy': 1})
  call dein#load_toml(s:toml_dir . '/dein_ddc.toml', {'lazy': 1})
  call dein#load_toml(s:toml_dir . '/dein_ddu.toml')
  call dein#load_toml(s:toml_dir . '/dein_ft.toml')

  "finalize
  call dein#end()
  call dein#save_state()
endif

if !has("nvim")
  syntax enable
  filetype plugin indent on
  let &t_8f = "\<Esc>[38;2;%lu;%lu;%lum"
  let &t_8b = "\<Esc>[48;2;%lu;%lu;%lum"
endif

if dein#check_install()
  call dein#install()
endif

" end dein settings---------------------------------------

let g:do_filetype_lua = 1
let g:did_load_filetypes = 0

filetype on

if has('vim_starting') && !empty(argv())
  call vimrc#on_filetype()
endif

if filereadable(expand('~/.vim/secret.vim'))
  source ~/.vim/secret.vim
endif

if vimrc#is_windows()
  let g:python3_host_prog = $USERPROFILE . '\AppData\Local\Programs\Python\Python39\python.EXE'
  set shell=cmd.exe
else
  " use virtualenv
  " let s:py3_dir = expand('~/.vim/python3/')
  " let g:python3_host_prog = s:py3_dir . 'bin/python3'
  " let $PATH = s:py3_dir . 'bin:' . $PATH
endif

" make chdir() change tab local directory
call execute('tcd ' . getcwd())

source ~/dotfiles/nvim/map.rc.vim

source ~/dotfiles/nvim/options.rc.vim

let g:loaded_2html_plugin      = 1
let g:loaded_logiPat           = 1
let g:loaded_getscriptPlugin   = 1
let g:loaded_gzip              = 1
" let g:loaded_man               = 1
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
