nnoremap <Space>d <cmd>Ddu source<CR>
nnoremap <Space>a <cmd>Ddu file_external<CR>
nnoremap <Space>f <cmd>Ddu file_external -source-option-path=~/dotfiles<CR>
nnoremap <Space>h <cmd>Ddu help -name=help<CR>
nnoremap <Space>o <cmd>Ddu file_old<CR>
nnoremap <Space>s <cmd>Ddu directory_rec<CR>
nnoremap <Space>n <cmd>Ddu ghq<CR>
nnoremap <Space>b <cmd>Ddu buffer<CR>
nnoremap <Space>r <cmd>Ddu -resume<CR>
nnoremap <Space>g <cmd>DduRgLive<CR>
nnoremap <Space>m <cmd>Ddu man<CR>
nnoremap g0 <cmd>LspDocumentSymbols<CR>
" nnoremap <silent> <C-f> <cmd>DduFiler<CR>

cnoremap <expr><silent> <C-t>
    \ "<C-u><ESC><cmd>Ddu command_history -input='" .
    \ getcmdline() . "'<CR>"

command! DduRgGlob call <SID>ddu_rg_with_glob()
function! s:ddu_rg_with_glob() abort
  let pattern = input('search pattern: ')
  let glob = input('glob pattern: ')
  let args = ['--json', '--ignore-case']
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

command! DduRgLive call <SID>ddu_rg_live()
function! s:ddu_rg_live() abort
  let column = &columns
  let line = &lines
  let win_height = min([line - 10, 45])
  let win_row = (line - win_height)/2

  let win_width = min([column/2 - 5, 80])
  let win_col = column/2 - win_width
  call ddu#start({
        \ 'sources': [{'name': 'rg', 'options': {'matchers': []}}],
        \ 'volatile': v:true,
        \ 'uiParams': {'ff': {
        \   'split': has('nvim') ? 'floating' : 'horizontal',
        \   'autoAction': {'name': 'preview'},
        \   'filterSplitDirection': 'floating',
        \   'filterFloatingPosition': 'top',
        \   'previewFloating': v:true,
        \   'previewHeight': win_height,
        \   'previewVertical': v:true,
        \   'previewWidth': win_width,
        \   'winCol': win_col,
        \   'winRow': win_row,
        \   'winWidth': win_width,
        \   'winHeight': win_height,
        \   'ignoreEmpty': v:false,
        \   'autoResize': v:false,
        \ }},
        \ })
endfunction

command! DduRgPreview call <SID>ddu_rg_preview()
command! DeinUpdate call <SID>open_preview_ddu([{'name': 'dein_update'}])
command! LspDocumentSymbols call <SID>open_preview_ddu([{'name': 'nvim_lsp_document_symbol'}])
" command! LspDocumentSymbols call ddu#start({'sources': [{'name': 'nvim_lsp_document_symbol'}], 'ui': 'filer'})

function! s:ddu_rg_preview() abort
  let input = input("Pattern: ")
  if input == ""
    return
  endif
  call s:open_preview_ddu([{'name': 'rg', 'params': {'input': input}}])
endfunction

function! s:open_preview_ddu(sources) abort
  let column = &columns
  let line = &lines
  let win_height = min([line - 10, 45])
  let win_row = (line - win_height)/2

  let win_width = min([column/2 - 5, 80])
  let win_col = column/2 - win_width
  call ddu#start({
        \ 'sources': a:sources,
        \ 'uiParams': {'ff': {
        \   'split': has('nvim') ? 'floating' : 'horizontal',
        \   'autoAction': {'name': 'preview'},
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

command! DduFiler call <SID>ddu_filer()
function! s:ddu_filer() abort
  call ddu#start({
        \   'ui': 'filer',
        \   'name': 'filer',
        \   'resume': v:true,
        \   'sources': [{
        \     'name': 'file', 
        \     'options': {
        \       'columns': ["filename"],
        \     },
        \   }],
        \   'actionOptions': {
        \     'narrow': {
        \       'quit': v:false,
        \     },
        \   },
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
      \     'line': {
      \       'matchers': ['matcher_kensaku'],
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
	    \     'man': {
      \       'defaultAction': 'open',
	    \     },
      \     'ghq': {
      \       'defaultAction': 'cd',
      \       'path': '~',
      \     },
      \     'command_history': {
      \       'defaultAction': 'execute',
      \     },
      \     'dein_update': {
      \       'matchers': ['matcher_dein_update'],
      \     },
      \   },
      \   'kindOptions': {
      \     'file': {
      \       'defaultAction': 'open',
      \     },
      \     'action': {
      \       'defaultAction': 'do',
      \     },
      \     'dein_update': {
      \       'defaultAction': 'viewDiff',
      \     },
      \     'gin_action': {
      \       'defaultAction': 'execute',
      \     },
	    \     'source': {
	    \       'defaultAction': 'execute',
	    \     },
	    \     'ui_select': {
	    \       'defaultAction': 'select',
	    \     },
      \   },
      \   'actionOptions': {
      \     'echo': {
      \       'quit': v:false,
      \     },
      \     'echoDiff': {
      \       'quit': v:false,
      \     },
      \   },
      \   'filterParams': {
      \     'matcher_fzy': {
      \       'hlGroup': 'Special',
      \     },
      \     'matcher_kensaku': {
      \       'highlightMatched': 'Search',
      \     },
      \   },
      \   'sourceParams': {
      \     'file_external': {
      \       'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
      \                '-t', 'f']
      \     },
      \     'directory_rec': {
      \       'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', 
      \                '-t', 'd']
      \     },
      \     'rg': {
      \       'args': ['--json', '--ignore-case'], 
      \       'highlights': {
      \         'path': 'SpecialComment',
      \         'lineNr': 'LineNr',
      \         'word': 'Constant',
      \       }
      \     },
      \     'ghq': {'cmd': ['ghq', 'list', '-p']},
      \   },
      \   'uiParams': {
      \     'ff': {
      \       'split': has('nvim') ? 'floating' : 'horizontal',
      \       'filterSplitDirection': 'floating',
      \       'filterFloatingPosition': 'top',
      \       'ignoreEmpty': v:true,
      \       'autoResize': v:true,
      \     },
      \     'filer': {
      \       'split': "no",
      \     },
      \   },
      \ })

  augroup MyDduSetup
    autocmd!
    autocmd FileType ddu-ff call s:ddu_my_settings()
    autocmd FileType ddu-ff-filter call s:ddu_filter_my_settings()
    autocmd FileType ddu-filer call s:ddu_filer_my_settings()
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
    nnoremap <buffer> o
    \ <Cmd>call ddu#ui#ff#do_action('expandItem',
    \ {'mode': 'toggle'})<CR>
    nnoremap <buffer> O
    \ <Cmd>call ddu#ui#ff#do_action('expandItem',
    \ {'maxLevel': -1})<CR>

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
  endfunction

  function! s:ddu_filter_my_settings() abort
    nnoremap <buffer><silent> q <cmd>quit<CR>
    inoremap <buffer><silent> <CR> <Esc><Cmd>call ddu#ui#ff#close()<CR>
    inoremap <buffer><silent> <C-o> <Esc><Cmd>call ddu#ui#ff#close()<CR>
  endfunction

	function! s:ddu_filer_my_settings() abort
    nnoremap <buffer> <Space>
    \ <Cmd>call ddu#ui#filer#do_action('toggleSelectItem')<CR>
    nnoremap <buffer> *
    \ <Cmd>call ddu#ui#filer#do_action('toggleAllItems')<CR>
    nnoremap <buffer> a
    \ <Cmd>call ddu#ui#filer#do_action('chooseAction')<CR>
    nnoremap <buffer> q
    \ <Cmd>call ddu#ui#filer#do_action('quit')<CR>
    nnoremap <buffer> o
    \ <Cmd>call ddu#ui#filer#do_action('expandItem',
    \ {'mode': 'toggle'})<CR>
    nnoremap <buffer> O
    \ <Cmd>call ddu#ui#filer#do_action('expandItem',
    \ {'maxLevel': -1})<CR>
    "nnoremap <buffer> O
    "\ <Cmd>call ddu#ui#filer#do_action('collapseItem')<CR>
    nnoremap <buffer> c
    \ <Cmd>call ddu#ui#filer#multi_actions([
    \ ['itemAction', {'name': 'copy'}],
    \ ['clearSelectAllItems'],
    \ ])<CR>
    nnoremap <buffer> d
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'trash'})<CR>
    nnoremap <buffer> D
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'delete'})<CR>
    nnoremap <buffer> m
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'move'})<CR>
    nnoremap <buffer> r
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'rename'})<CR>
    nnoremap <buffer> x
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'executeSystem'})<CR>
    nnoremap <buffer> P
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'paste'})<CR>
    nnoremap <buffer> K
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'newDirectory'})<CR>
    nnoremap <buffer> N
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'newFile'})<CR>
    nnoremap <buffer> ~
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'narrow', 'params': {'path': expand('~')}})<CR>
    nnoremap <buffer> h
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'narrow', 'params': {'path': ".."}})<CR>
    nnoremap <buffer> I
    \ <Cmd>call ddu#ui#filer#do_action('itemAction',
    \ {'name': 'narrow', 'params': {'path':
    \  fnamemodify(input('New cwd: ', b:ddu_ui_filer_path, 'dir'), ':p')}})<CR>
    nnoremap <buffer> >
    \ <Cmd>call ddu#ui#filer#do_action('updateOptions', {
    \   'sourceOptions': {
    \     'file': {
    \       'matchers': ToggleHidden('file'),
    \     },
    \   },
    \ })<CR>
    nnoremap <buffer> <C-l>
    \ <Cmd>call ddu#ui#filer#do_action('checkItems')<CR>
    nnoremap <buffer><expr> <CR>
    \ ddu#ui#filer#is_tree() ?
    \ "<Cmd>call ddu#ui#filer#do_action('itemAction', {'name': 'narrow'})<CR>" :
    \ "<Cmd>call ddu#ui#filer#do_action('itemAction', {'name': 'open'})<CR>"
    nnoremap <buffer><expr> l
    \ ddu#ui#filer#is_tree() ?
    \ "<Cmd>call ddu#ui#filer#do_action('itemAction', {'name': 'narrow'})<CR>" :
    \ "<Cmd>call ddu#ui#filer#do_action('itemAction', {'name': 'open'})<CR>"
  endfunction

    function! ToggleHidden(name)
      let current = ddu#custom#get_current(b:ddu_ui_name)
      let source_options = get(current, 'sourceOptions', {})
      let source_options_name = get(source_options, a:name, {})
      let matchers = get(source_options_name, 'matchers', [])
      return empty(matchers) ? ['matcher_hidden'] : []
    endfunction

endfunction
