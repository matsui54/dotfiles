let s:dein_dir = expand('~/.cache/dein')
let s:dein_repo_dir = s:dein_dir . '/repos/github.com/Shougo/dein.vim' 
let s:toml_dir = expand('~/.config/nvim')

if !isdirectory(s:dein_dir)
	execute '!git clone https://github.com/Shougo/dein.vim' s:dein_repo_dir
endif
execute 'set runtimepath+=' . s:dein_repo_dir
set runtimepath+=~/OxfDictionary.nvim

if !has("python3")
	execute '!pip3 install --user pynvim'
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

let g:OxfDictionary#app_id='3fc46c58'
let g:OxfDictionary#app_key='c4603e15e4eb3f7219bd477823507ad6'

set number
set title
set tabstop=2
set shiftwidth=2
set smartindent
set clipboard=unnamedplus
set splitright
set showmatch

colorscheme PaperColor
highlight Normal ctermbg=none
highlight LineNr ctermbg=none

augroup vimrc 
	autocmd!
	autocmd VimEnter * NoMatchParen
augroup END

source ~/nvim/plugins/keymappings.vim

if has("unix")
	augroup im_change
		autocmd InsertEnter * :call system('fcitx-remote -c')
		autocmd InsertLeave * :call system('fcitx-remote -o')
		autocmd VimEnter * :call system('fcitx-remote -o')
		autocmd VimLeave * :call system('fcitx-remote -c')
	augroup END
endif
