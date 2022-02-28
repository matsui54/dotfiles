nnoremap <silent> <Space>a <cmd>Ddu file_external<CR>
nnoremap <silent> <Space>f <cmd>Ddu file_external -source-param-path=~/dotfiles<CR>
nnoremap <silent> <Space>h <cmd>Ddu help<CR>
nnoremap <silent> <Space>o <cmd>Ddu file_old<CR>
nnoremap <silent> <Space>s <cmd>Ddu directory_rec<CR>
nnoremap <silent> <Space>n <cmd>Ddu ghq<CR>
cnoremap <expr><silent> <C-t>
    \ "<C-u><ESC><cmd>Ddu command_history -ui-param-startFilter -input='" .
    \ getcmdline() . "'<CR>"

function! Ddu_setup() abort
  call ddu#custom#alias('source', 'directory_rec', 'file_external')
  call ddu#custom#patch_global({
      \   'ui': 'ff',
      \   'profile': v:true,
      \   'sourceOptions' : {
      \     '_' : {
      \       'ignoreCase': v:true,
      \       'matchers': ['matcher_fzy'],
      \     },
	    \     'dein': {
	    \       'defaultAction': 'cd',
	    \     },
	    \     'highlight': {
	    \       'defaultAction': 'edit',
	    \     },
	    \     'help': {
	    \       'defaultAction': 'open',
	    \     },
	    \     'file_external': {
	    \       'defaultAction': 'open',
	    \     },
	    \     'directory_rec': {
      \       'defaultAction': 'cd',
	    \     },
	    \     'ghq': {
      \       'defaultAction': 'cd',
	    \     },
	    \     'command_history': {
      \       'defaultAction': 'execute',
	    \     },
      \   },
	    \   'kindOptions': {
	    \     'file': {
	    \       'defaultAction': 'open',
	    \     },
      \     'action': {
      \       'defaultAction': 'do',
      \     },
	    \   },
      \   'uiParams': {
      \     'ff': {
      \       'split': has('nvim') ? 'floating' : 'horizontal',
      \       'filterSplitDirection': 'floating',
      \       'filterFloatingPosition': 'top',
      \       'autoResize': v:true,
      \       'ignoreEmpty': v:true,
      \     }
      \   },
      \ })

  " Set default sources
  call ddu#custom#patch_global('sourceParams', {
        \  'file_external': {
        \    'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
        \             '-t', 'f']
        \  },
        \  'directory_rec': {
        \    'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
        \             '-t', 'd']
        \  },
        \  'ghq': {'display': 'raw'}
        \ })

  augroup MyDduSetup
    autocmd!
    autocmd FileType ddu-ff call s:ddu_my_settings()
    autocmd FileType ddu-ff-filter call s:ddu_filter_my_settings()
  augroup END
  function! s:ddu_my_settings() abort
    nnoremap <buffer><silent> <CR>
    \ <Cmd>call ddu#ui#ff#do_action('itemAction')<CR>
    nnoremap <buffer><silent> ,
    \ <Cmd>call ddu#ui#ff#do_action('toggleSelectItem')<CR>j
    nnoremap <buffer><silent> i
    \ <Cmd>call ddu#ui#ff#do_action('openFilterWindow')<CR>
    nnoremap <buffer><silent> q
    \ <Cmd>call ddu#ui#ff#do_action('quit')<CR>
    nnoremap <buffer><silent> E
    \ <Cmd>call ddu#ui#ff#do_action('itemAction',
    \ {'name': 'open', 'params': {'command': 'vsplit'}})<CR>
    nnoremap <buffer><silent> t
    \ <Cmd>call ddu#ui#ff#do_action('itemAction',
    \ {'name': 'open', 'params': {'command': 'tabedit'}})<CR>
    nnoremap <buffer><silent> <C-l>
    \ <Cmd>call ddu#ui#ff#do_action('refreshItems')<CR>
    nnoremap <buffer><silent> p
    \ <Cmd>call ddu#ui#ff#do_action('preview')<CR>
    nnoremap <buffer><silent> a
    \ <Cmd>call ddu#ui#ff#do_action('chooseAction')<CR>
    " nnoremap <buffer><silent> c
    "\ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'cd'})<CR>
    nnoremap <buffer><silent> d
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'delete'})<CR>
    nnoremap <buffer><silent> e
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'edit'})<CR>
    nnoremap <buffer><silent> N
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'new'})<CR>
    nnoremap <buffer><silent> r
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'quickfix'})<CR>
    nnoremap <buffer><silent> u
    \ <Cmd>call ddu#ui#ff#do_action('updateOptions', {
    \   'sourceOptions': {
    \     '_': {
    \       'matchers': [],
    \     },
    \   },
    \ })<CR>
  endfunction

  function! s:ddu_filter_my_settings() abort
    nnoremap <buffer><silent> q <cmd>quit<CR>
    inoremap <buffer><silent> <CR> <Esc><Cmd>close<CR>
    inoremap <buffer><silent> <C-o> <Esc><Cmd>close<CR>
  endfunction
endfunction
