nnoremap <silent> <Space>a <cmd>Ddu file_external<CR>
nnoremap <silent> <Space>f <cmd>Ddu file_external -source-param-path=~/dotfiles
      \ -ui-param-startFilter=v:true<CR>
nnoremap <silent> <Space>h <cmd>Ddu help -ui-param-startFilter=v:true<CR>

function! Ddu_setup() abort
  call ddu#custom#patch_global({
      \   'ui': 'std',
      \   'sourceOptions' : {
      \     '_' : {
      \       'ignoreCase': v:true,
      \       'matchers': ['matcher_fzf'],
      \     }
      \   },
      \   'uiParams': {
      \     'std': {
      \     }
      \   },
      \ })

  " Set default sources
  call ddu#custom#patch_global('sourceParams', {
        \ 'file_external': {'cmd': ['fd', '.', '-H', '-E', '.git', '-E', '__pycache__', '-t', 'f']}
        \ })


  " Call default sources
  "call ddu#start({})

  " Set buffer-name specific configuration
  "call ddu#custom#patch_local('files', {
  "    \ 'sources': [
  "    \   {'name': 'file', 'params': {}},
  "    \   {'name': 'file_old', 'params': {}},
  "    \ ],
  "    \ })

  " Specify buffer name
  "call ddu#start({'name': 'files'})

  " Specify source with params
  " call ddu#start([
  "\ {'name': 'fd', 'params': {'cmd': ['rg', '--files', '--glob', '!.git', '--color', 'never']}}
  "\ ])

  augroup MyDduSetup
    autocmd!
    autocmd FileType ddu-std call s:ddu_my_settings()
    autocmd FileType ddu-std-filter call s:ddu_filter_my_settings()
  augroup END
  function! s:ddu_my_settings() abort
    nnoremap <buffer><silent> <CR>
    \ <Cmd>call ddu#ui#std#do_action('itemAction')<CR>
    nnoremap <buffer><silent> ,
    \ <Cmd>call ddu#ui#std#do_action('toggleSelectItem')<CR>j
    nnoremap <buffer><silent> i
    \ <Cmd>call ddu#ui#std#do_action('openFilterWindow')<CR>
    nnoremap <buffer><silent> q
    \ <Cmd>call ddu#ui#std#do_action('quit')<CR>
  endfunction

  function! s:ddu_filter_my_settings() abort
    nnoremap <buffer><silent> q <cmd>quit<CR>
    inoremap <buffer><silent> <CR> <Esc><Cmd>close<CR>
    inoremap <buffer><silent> <C-o> <Esc><Cmd>close<CR>
  endfunction
endfunction
