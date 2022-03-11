nnoremap <Space>d :Ddu<Space>
nnoremap <Space>a <cmd>Ddu file_external<CR>
nnoremap <Space>f <cmd>Ddu file_external -source-param-path=~/dotfiles<CR>
nnoremap <Space>h <cmd>Ddu help -name=help<CR>
nnoremap <Space>o <cmd>Ddu file_old<CR>
nnoremap <Space>s <cmd>Ddu directory_rec<CR>
nnoremap <Space>n <cmd>Ddu ghq<CR>
nnoremap <Space>b <cmd>Ddu buffer<CR>
nnoremap <Space>r <cmd>Ddu -resume<CR>

cnoremap <expr><silent> <C-t>
    \ "<C-u><ESC><cmd>Ddu command_history -ui-param-startFilter -input='" .
    \ getcmdline() . "'<CR>"

command! DduRgGlob call <SID>ddu_rg_with_glob()
function! s:ddu_rg_with_glob() abort
  let pattern = input('search pattern: ')
  let glob = input('glob pattern: ')
  let args = ['--json']
  if glob != ''
    let args += ['-g', glob]
  endif
  call ddu#start({
        \ 'sources': [{
        \   'name': 'rg', 
        \   'params': {'input': pattern, 'args': args}
        \ }],
        \ })
endfunction

command! DduPreview call <SID>open_preview_ddu()

function! s:open_preview_ddu() abort
  let column = &columns
  let line = &lines
  let win_height = min([line - 10, 45])
  let win_row = (line - win_height)/2

  let win_width = min([column/2 - 5, 80])
  let win_col = column/2 - win_width
  call ddu#start({
        \ 'sources': [{'name': 'rg', 'params': {'input': 'vim'}}],
        \ 'name': 'preview',
        \ 'uiParams': {'ff': {
        \   'split': has('nvim') ? 'floating' : 'horizontal',
        \   'filterSplitDirection': 'floating',
        \   'filterFloatingPosition': 'top',
        \   'previewFloating': v:true,
        \   'previewHeight': win_height,
        \   'previewVertical': v:true,
        \   'previewWidth': win_width,
        \   'ignoreEmpty': v:true,
        \   'autoResize': v:false,
        \   'winCol': win_col,
        \   'winRow': win_row,
        \   'winWidth': win_width,
        \   'winHeight': win_height,
        \ }},
        \ })
endfunction

function! Ddu_setup() abort
  call ddu#custom#alias('source', 'directory_rec', 'file_external')
  call ddu#custom#alias('source', 'ghq', 'file_external')
  call ddu#custom#patch_global({
      \   'ui': 'ff',
      \   'profile': v:false,
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
	    \     'man': {
      \       'defaultAction': 'open',
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
      \       'ignoreEmpty': v:true,
      \       'autoResize': v:true,
      \     }
      \   },
      \ })

  " Set default sources
  call ddu#custom#patch_global('sourceParams', {
        \   'file_external': {
        \     'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
        \              '-t', 'f']
        \   },
        \   'directory_rec': {
        \     'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
        \              '-t', 'd']
        \   },
        \   'rg': {
        \     'args': ['--json'], 
        \     'highlights': {
        \       'path': 'SpecialComment',
        \       'lineNr': 'LineNr',
        \       'word': 'Constant',
        \     }
        \   },
        \   'ghq': {'cmd': ['ghq', 'list', '-p'], 'path': '~/'},
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
    nnoremap <buffer><silent> p
    \ <Cmd>call ddu#ui#ff#do_action('preview')<CR>
    nnoremap <buffer><silent> a
    \ <Cmd>call ddu#ui#ff#do_action('chooseAction')<CR>
    nnoremap <buffer><silent> c
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'cd'})<CR>
    nnoremap <buffer><silent> d
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'delete'})<CR>
    nnoremap <buffer><silent> e
    \ <Cmd>call ddu#ui#ff#do_action('itemAction', {'name': 'edit'})<CR>

    if b:ddu_ui_name ==# 'help'
      nnoremap <buffer><silent> E
      \ <Cmd>call ddu#ui#ff#do_action('itemAction',
      \ {'name': 'vsplit'})<CR>
      nnoremap <buffer><silent> t
      \ <Cmd>call ddu#ui#ff#do_action('itemAction',
      \ {'name': 'tabopen'})<CR>
    else
      nnoremap <buffer><silent> E
      \ <Cmd>call ddu#ui#ff#do_action('itemAction',
      \ {'name': 'open', 'params': {'command': 'vsplit'}})<CR>
      nnoremap <buffer><silent> t
      \ <Cmd>call ddu#ui#ff#do_action('itemAction',
      \ {'name': 'open', 'params': {'command': 'tabedit'}})<CR>
      nnoremap <buffer><silent> S
      \ <Cmd>call ddu#ui#ff#do_action('itemAction',
      \ {'name': 'open', 'params': {'command': 'split'}})<CR>
    endif

    if b:ddu_ui_name ==# 'preview'
      augroup MyDduPreview
        autocmd!
        autocmd CursorMoved <buffer> call ddu#ui#ff#do_action('previewBat')
      augroup END
    endif
  endfunction

  function! s:ddu_filter_my_settings() abort
    nnoremap <buffer><silent> q <cmd>quit<CR>
    inoremap <buffer><silent> <CR> <Esc><Cmd>close<CR>
    inoremap <buffer><silent> <C-o> <Esc><Cmd>close<CR>
  endfunction
endfunction
