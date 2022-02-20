" pum.vim
if v:true
  call ddc#custom#patch_global('completionMenu', 'pum.vim')

  inoremap <silent><expr> <TAB>
        \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
        \ (col('.') <= 1 <Bar><Bar> getline('.')[col('.') - 2] =~# '\s') ?
        \ '<TAB>' : ddc#manual_complete()
  inoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
  inoremap <C-n>   <Cmd>call pum#map#select_relative(+1)<CR>
  inoremap <C-p>   <Cmd>call pum#map#select_relative(-1)<CR>
  inoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
  inoremap <C-e>   <Cmd>call pum#map#cancel()<CR>

  call pum#set_option('setline_insert', v:false)

  " command line completion
  call ddc#custom#patch_global('autoCompleteEvents',
        \ ['InsertEnter', 'TextChangedI', 'TextChangedP', 'CmdlineChanged'])
  cnoremap <silent><expr> <TAB>
        \ pum#visible() ? '<Cmd>call pum#map#insert_relative(+1)<CR>' :
        \ ddc#manual_complete()
  cnoremap <S-Tab> <Cmd>call pum#map#insert_relative(-1)<CR>
  cnoremap <C-y>   <Cmd>call pum#map#confirm()<CR>
  cnoremap <C-e>   <Cmd>call pum#map#cancel()<CR>
  autocmd MyAutoCmd CmdlineEnter * call CommandlinePre()
  autocmd MyAutoCmd CmdlineLeave * call CommandlinePost()

  function! CommandlinePre() abort
    call denops#plugin#wait('ddc')

    " Overwrite sources
    let current = ddc#custom#get_current()
    if exists('s:in_cmdline') && s:in_cmdline
      return
    endif

    let s:prev_buffer_sources = current
    if getcmdtype() == '/'
      call ddc#custom#patch_buffer('sources', ['buffer', 'cmdline-history'])
    elseif getcmdtype() == '@'
      call ddc#custom#patch_buffer('sources', ['buffer'])
    else
      call ddc#custom#patch_buffer('sources', ['cmdline', 'buffer'])
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
  call ddc#custom#patch_global('sources', ['nvim-lsp', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'])
else
  call ddc#custom#patch_global('sources', ['vim-lsp', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'])
endif
call ddc#custom#patch_global('postFilters', ["my_filter"])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy'],
      \   'sorters': ['sorter_fuzzy'],
      \   'converters': ['converter_remove_overlap', 'converter_truncate'],
      \   'ignoreCase': v:true,
      \ },
      \ 'around': {'mark': 'A'},
      \ 'cmdline': {
      \   'mark': 'cmd',
      \   'forceCompletionPattern': "\\s|/", 
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'cmdline-history': {
      \   'matchers': ['matcher_head'], 
      \   'sorters': [], 
      \   'mark': 'hist',
      \   'minAutoCompleteLength': 1,
      \   'maxCandidates': 3,
      \ },
      \ 'dictionary': {
      \   'matchers': ['matcher_editdistance'], 
      \   'sorters': [], 
      \   'converters': ['converter_fuzzy'],
      \   'maxCandidates': 6,
      \   'mark': 'D', 
      \   'minAutoCompleteLength': 3,
      \ },
      \ 'necovim': {'mark': 'neco', 'maxCandidates': 6},
      \ 'nvim-lsp': {
      \   'mark': 'lsp', 
      \   'dup': v:true, 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \   'minAutoCompleteLength': 1,
      \ },
      \ 'vim-lsp': {
      \   'mark': 'lsp', 
      \   'dup': v:true, 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \ },
      \ 'buffer': {'mark': 'B', 'maxCandidates': 10},
	    \ 'file': {
	    \   'mark': 'F',
	    \   'isVolatile': v:true,
	    \   'forceCompletionPattern': '\S/\S*',
      \ },
      \ 'vsnip': {'dup': v:true},
      \ 'skkeleton': {
      \   'mark': 'skk',
      \   'matchers': ['skkeleton'],
      \   'sorters': [],
      \   'minAutoCompleteLength': 2,
      \ },
      \ })
call ddc#custom#patch_global('sourceParams', {
      \ 'around': {'maxSize': 500},
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
      \ 'converter_truncate': {'maxAbbrWidth': 60, 'maxInfo': 500, 'ellipsis': '...'},
      \ 'converter_fuzzy': {'hlGroup': 'Title'},
      \ 'my_filter': {'excludeSources': ["dictionary", "skkeleton"]},
      \ })

call ddc#custom#patch_global('specialBufferCompletion', v:true)
call ddc#custom#patch_filetype(
      \ ['denite-filter', 'ddu-ff-filter',  'TelescopePrompt'], 'specialBufferCompletion', v:false
      \ )

call ddc#custom#patch_filetype(['toml'], {
      \ 'sources': ['necovim', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'],
      \ })
" include @ for snippet
call ddc#custom#patch_filetype(
      \ ['tex'], {
      \ 'keywordPattern': '[a-zA-Z0-9_@]*',
      \ 'sourceOptions': {
      \   'vsnip': {'forceCompletionPattern': '@'},
      \ },
      \ })
call ddc#custom#patch_filetype(['zsh'], 'sourceOptions', {
      \ 'zsh': {'mark': 'Z'},
      \ })

call ddc#enable()
