" dein settings--------------------------------------------
let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim' 
let s:toml_dir = expand('~/dotfiles/nvim')

if !isdirectory(s:dein_dir)
  execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath+=' . s:dein_repo_dir

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

if dein#check_install()
  call dein#install()
endif

call map(dein#check_clean(), "delete(v:val, 'rf')")
call dein#recache_runtimepath()
" end dein settings---------------------------------------

let g:OxfDictionary#app_id='3fc46c58'
let g:OxfDictionary#app_key='c4603e15e4eb3f7219bd477823507ad6'
set runtimepath+=/home/haruki/work/OxfDictionary.nvim

source ~/dotfiles/nvim/map.rc.vim

source ~/dotfiles/nvim/options.rc.vim
