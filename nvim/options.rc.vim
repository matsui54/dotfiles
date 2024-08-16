set title
set updatetime=500
set hidden
set laststatus=2
set signcolumn=yes

set expandtab
set tabstop=2
set shiftwidth=0
set smartindent

if executable("lemonade")
  let s:clp_cmd = "lemonade --no-fallback-messages"
  let g:clipboard = {
        \   'name': 'myClipboard',
        \   'copy': {
        \      '+': s:clp_cmd . ' copy',
        \      '*': s:clp_cmd . ' copy',
        \    },
        \   'paste': {
        \      '*': s:clp_cmd . ' paste',
        \      '+': s:clp_cmd . ' paste',
        \   },
        \   'cache_enabled': 1,
        \ }
elseif executable("win32yank")
  let s:clp_cmd = "win32yank"
  let g:clipboard = {
        \   'name': 'myClipboard',
        \   'copy': {
        \      '+': s:clp_cmd . ' -i',
        \      '*': s:clp_cmd . ' -i',
        \    },
        \   'paste': {
        \      '*': s:clp_cmd . ' -o',
        \      '+': s:clp_cmd . ' -o',
        \   },
        \   'cache_enabled': 1,
        \ }
endif

set clipboard=unnamedplus

set ignorecase
set smartcase

set showmatch
set matchpairs+=<:>

set undofile

set termguicolors

set completeopt-=preview

set splitright

set helplang=en,ja
language en_US.utf8

if filereadable(expand('/usr/share/dict/words'))
  set dictionary=/usr/share/dict/words
endif

if exists('&inccommand')
  set inccommand=nosplit
endif

if exists('&pumblend')
  set pumblend=30
endif

if exists('&winblend')
  set winblend=10
endif

" Don't show too many items
set pumheight=15

augroup MyAutoCmd
  autocmd!
  autocmd ColorScheme * call vimrc#color_settings(expand('<amatch>'))
  autocmd VimEnter * let t:defx_index = 1 | let g:tab_idx = 1
  autocmd TabNew * let t:defx_index = s:get_defx_idx()
  autocmd CmdwinEnter [:>] iunmap <buffer> <Tab>
  autocmd CmdwinEnter [:>] nunmap <buffer> <Tab>
  autocmd CursorHold * redrawtabline
augroup END

colorscheme shirotelin

function! s:get_defx_idx()
  let g:tab_idx += 1
  return g:tab_idx
endfunction

" tabline setting
set showtabline=2
set tabline=%!tabline#MyTabLine()

set mouse=nv

set isfname-==
