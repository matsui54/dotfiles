if exists('g:vscode')
  finish
endif

" dein settings--------------------------------------------
let g:dein#lazy_rplugins = v:true
let g:dein#auto_recache = !has('win32')
let g:dein#install_progress_type = 'floating'
let g:dein#install_check_diff = v:true

let s:dein_dir = stdpath('cache')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim'
let s:config_dir = stdpath('config')

let s:dein_toml = s:config_dir . '/dein.toml'
let s:dein_lazy_toml = s:config_dir . '/dein_lazy.toml'
let s:dein_ddc_toml = s:config_dir . '/dein_ddc.toml'
let s:dein_ddu_toml = s:config_dir . '/dein_ddu.toml'
let s:dein_ft_toml = s:config_dir . '/dein_ft.toml'

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
  call dein#load_toml(s:dein_toml, {'lazy': 0})
  call dein#load_toml(s:dein_lazy_toml, {'lazy': 1})
  call dein#load_toml(s:dein_ddc_toml, {'lazy': 0})
  call dein#load_toml(s:dein_ddu_toml, {'lazy': 0})
  call dein#load_toml(s:dein_ft_toml)

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

filetype plugin indent on
syntax enable

if filereadable(expand('~/.vim/secret.vim'))
  source ~/.vim/secret.vim
endif

if vimrc#is_windows()
  let &shell = executable('pwsh') ? 'pwsh' : 'powershell'
  let &shellcmdflag = '-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command [Console]::InputEncoding=[Console]::OutputEncoding=[System.Text.Encoding]::UTF8;'
  let &shellredir = '-RedirectStandardOutput %s -NoNewWindow -Wait'
  let &shellpipe = '2>&1 | Out-File -Encoding UTF8 %s; exit $LastExitCode'
  set shellquote= shellxquote=
endif

" make chdir() change tab local directory
call execute('tcd ' . getcwd())

execute "source " . s:config_dir . "/map.rc.vim"
execute "source " . s:config_dir . "/options.rc.vim"

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
