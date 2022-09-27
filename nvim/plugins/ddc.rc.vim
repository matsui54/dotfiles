" pum.vim
if v:true
  call ddc#custom#patch_global('completionMenu', 'pum.vim')
  call pum#set_option('setline_insert', v:false)
  call pum#set_option('scrollbar_char', '')

  if v:true
    function s:confirm()
      let info = pum#complete_info()
      let index = info.selected
      if skkeleton#is_enabled()
        if info.selected == -1
          call pum#map#insert_relative(1)
        endif
        return "\<Ignore>"
      endif
      if info.selected == -1
        call pum#map#select_relative(+1)
        let index = 0
      endif
      call pum#map#confirm()
      let complete_item = info.items[index]
      " wait for the candidate is inserted
      call timer_start(0, { -> vsnip_integ#on_complete_done(complete_item) })
      return "\<Ignore>"
    endfunction
    inoremap <silent><expr> <Tab>
          \ pum#visible() ? <SID>confirm() :
          \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
          \ '<TAB>' : ddc#manual_complete()
    inoremap <C-n>   <Cmd>call pum#map#select_relative(+1)<CR>
    inoremap <C-p>   <Cmd>call pum#map#select_relative(-1)<CR>
    inoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
    inoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
    cnoremap <silent><expr> <TAB>
          \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
          \ ddc#manual_complete()
    cnoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
    cnoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
  else
    inoremap <silent><expr> <TAB>
          \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
          \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
          \ '<TAB>' : ddc#manual_complete()
    inoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
    inoremap <C-n>   <Cmd>call pum#map#select_relative(+1)<CR>
    inoremap <C-p>   <Cmd>call pum#map#select_relative(-1)<CR>
    inoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
    inoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
    cnoremap <silent><expr> <TAB>
          \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
          \ ddc#manual_complete()
    cnoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
    cnoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
  endif

  " command line completion
  call ddc#custom#patch_global('autoCompleteEvents',
        \ ['InsertEnter', 'TextChangedI', 'TextChangedP', 'CmdlineChanged'])
  augroup MyDdcCmdLine
    autocmd!
    autocmd CmdlineEnter * call CommandlinePre()
    autocmd CmdlineLeave * call CommandlinePost()
  augroup END

  function! CommandlinePre() abort
    call denops#plugin#wait('ddc')

    " Overwrite sources
    let current = ddc#custom#get_current()
    if exists('s:in_cmdline') && s:in_cmdline
      return
    endif

    let s:prev_buffer_sources = current
    if getcmdtype() == '/'
      call ddc#custom#patch_buffer('cmdlineSources', ['buffer', 'cmdline-history'])
    elseif getcmdtype() == '@'
      call ddc#custom#patch_buffer('cmdlineSources', ['buffer'])
    else
      call ddc#custom#patch_buffer('cmdlineSources', ['cmdline', 'buffer', 'zsh'])
      " call ddc#custom#patch_buffer('sourceOptions', {
      "      \ 'zsh': {
      "      \   'forceCompletionPattern': "!.*", 
      "      \   'minAutoCompleteLength': 10000
      "      \ },
      "      \ })
    endif
    let s:in_cmdline = v:true

    " Enable command line completion
    call ddc#enable_cmdline_completion()
  endfunction
  function! CommandlinePost() abort
    " Restore sources
    call ddc#custom#set_buffer(s:prev_buffer_sources)
    let s:in_cmdline = v:false
  endfunction
else
  call ddc#custom#patch_global('completionMenu', 'native')
  inoremap <silent><expr> <TAB>
        \ pumvisible() ? '<C-n>' :
        \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
        \ '<TAB>' : ddc#manual_complete()
  inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"
endif

if has('nvim')
  call ddc#custom#patch_global('sources', ['buffer', 'around', 'vsnip', 'file', 'dictionary'])
else
  call ddc#custom#patch_global('sources', ['vim-lsp', 'buffer', 'around', 'vsnip', 'file', 'dictionary'])
endif
call ddc#custom#patch_global('postFilters', ['postfilter_score'])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy'],
      \   'sorters': ['sorter_fuzzy'],
      \   'converters': ['converter_remove_overlap', 'converter_truncate'],
      \   'ignoreCase': v:true,
      \ },
      \ 'around': {'mark': '[A]'},
      \ 'cmdline': {
      \   'mark': '[cmd]',
      \   'forceCompletionPattern': "\\s|/|-", 
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'cmdline-history': {
      \   'matchers': ['matcher_head'], 
      \   'sorters': [], 
      \   'mark': '[hist]',
      \   'minAutoCompleteLength': 1,
      \   'maxItems': 3,
      \ },
      \ 'dictionary': {
      \   'matchers': ['matcher_editdistance'], 
      \   'sorters': [], 
      \   'converters': ['converter_fuzzy'],
      \   'maxItems': 6,
      \   'mark': '[D]', 
      \   'minAutoCompleteLength': 3,
      \ },
      \ 'necovim': {'mark': '[neco]', 'maxItems': 6},
      \ 'nvim-lsp': {
      \   'mark': '[lsp]', 
      \   'dup': v:true, 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'vim-lsp': {
      \   'mark': '[lsp]', 
      \   'dup': v:true, 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'buffer': {'mark': '[B]', 'maxItems': 10},
      \ 'file': {
      \   'mark': '[F]',
      \   'isVolatile': v:true,
      \   'forceCompletionPattern': '\S/\S*',
      \ },
      \ 'file_rec': {
      \   'mark': '[P]',
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'emoji': {
      \	  'mark': '[emoji]',
      \   'dup': v:true, 
      \	  'matcherKey': 'kind',
      \   'minAutoCompleteLength': 1,
      \	},
      \ 'vsnip': {
      \	  'mark': '[V]',
      \   'dup': v:true, 
      \	},
      \ 'skkeleton': {
      \   'mark': '[skk]',
      \   'matchers': ['skkeleton'],
      \   'sorters': [],
      \   'isVolatile': v:true,
      \   'minAutoCompleteLength': 2,
      \ },
      \ 'zsh': {
      \   'mark': '[Z]',
      \   'forceCompletionPattern': "^!.*", 
      \   'minAutoCompleteLength': 10000
      \ },
      \ })
call ddc#custom#patch_global('sourceParams', {
      \ 'around': {'maxSize': 500},
      \ 'file_rec': {
      \   'cmd': ['fd', '--max-depth', '5'],
      \ },
      \ 'buffer': {'forceCollect': v:true, 'fromAltBuf': v:true, 'bufNameStyle': "basename"},
      \ 'dictionary': {'smartCase': v:true, 'showMenu': v:false},
      \ 'nvim-lsp': {'kindLabels': {
      \    "Text": " Text",
      \    "Method": " Method",
      \    "Function": " Function",
      \    "Constructor": " Constructor",
      \    "Field": "ﰠ Field",
      \    "Variable": " Variable",
      \    "Class": "ﴯ Class",
      \    "Interface": " Interface",
      \    "Module": " Module",
      \    "Property": "ﰠ Property",
      \    "Unit": "塞 Unit",
      \    "Value": " Value",
      \    "Enum": " Enum",
      \    "Keyword": " Keyword",
      \    "Snippet": " Snippet",
      \    "Color": " Color",
      \    "File": " File",
      \    "Reference": " Reference",
      \    "Folder": " Folder",
      \    "EnumMember": " EnumMember",
      \    "Constant": " Constant",
      \    "Struct": "פּ Struct",
      \    "Event": " Event",
      \    "Operator": " Operator",
      \    "TypeParameter": "TypeParameter"
      \ }},
      \ })
call ddc#custom#patch_global('filterParams', {
      \ 'converter_truncate': {
      \   'maxAbbrWidth': 60, 
      \   'maxInfo': 500, 
      \   'maxMenuWidth': 0, 
      \   'ellipsis': '...'
      \ },
      \ 'converter_fuzzy': {'hlGroup': 'Title'},
      \ 'postfilter_score': {
      \   'excludeSources': ["dictionary", "skkeleton", "emoji"],
      \ },
      \ })

call ddc#custom#patch_global('specialBufferCompletion', v:true)
call ddc#custom#patch_filetype(
      \ ['denite-filter', 'ddu-ff-filter',  'TelescopePrompt'], 'specialBufferCompletion', v:false
      \ )

call ddc#custom#patch_filetype(['toml'], {
      \ 'sources': ['necovim', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'],
      \ })
call ddc#custom#patch_filetype(['zsh'], {
      \ 'sources': ['zsh', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'],
      \ })
" include @ for snippet
call ddc#custom#patch_filetype(
      \ ['tex'], {
      \ 'keywordPattern': '[a-zA-Z0-9_@]*',
      \ 'sourceOptions': {
      \   'vsnip': {'forceCompletionPattern': '@'},
      \ },
      \ })

call ddc#enable()

function! s:patch_onetime(option) abort
  if exists('s:in_onetime') && s:in_onetime
    return
  endif

  let s:prev_buffer_option = ddc#custom#get_current()

  call ddc#custom#patch_buffer(a:option)
  let s:in_onetime = v:true
  augroup DdcOnetime
    autocmd!
    autocmd User PumCompleteDone ++once call s:reset_onetime()
    autocmd CompleteDone,InsertLeave <buffer> ++once call s:reset_onetime()
  augroup END
  return ddc#map#manual_complete()
  " return "\<Ignore>"
endfunction

function! s:reset_onetime() abort
  autocmd! DdcOnetime
  call ddc#custom#set_buffer(s:prev_buffer_option)
  let s:in_onetime = v:false
endfunction

inoremap <expr> <C-x><C-f> <SID>patch_onetime({
      \ 'sources': ['file_rec'],
      \ 'sourceParams': {
      \   'file_rec': {'path': expand('%:h')},
      \ },
      \ })
inoremap <expr> <C-x>; <SID>patch_onetime({'sources': ['emoji']})

augroup MyDdcSkkeleton
  autocmd!
  autocmd User skkeleton-enable-pre call s:skkeleton_pre()
  autocmd User skkeleton-disable-pre call s:skkeleton_post()
augroup END
function! s:skkeleton_pre() abort
  " Overwrite sources
  inoremap <C-n>   <Cmd>call pum#map#insert_relative(+1)<CR>
  inoremap <C-p>   <Cmd>call pum#map#insert_relative(-1)<CR>
  let s:prev_buffer_config = ddc#custom#get_buffer()
  call ddc#custom#patch_buffer('sources', ['skkeleton'])
endfunction
function! s:skkeleton_post() abort
  " Restore sources
  inoremap <C-n>   <Cmd>call pum#map#select_relative(+1)<CR>
  inoremap <C-p>   <Cmd>call pum#map#select_relative(-1)<CR>
  call ddc#custom#set_buffer(s:prev_buffer_config)
endfunction
