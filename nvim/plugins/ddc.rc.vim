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

if has('nvim')
  call ddc#custom#patch_global('sources', ['nvim-lsp', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'])
else
  call ddc#custom#patch_global('sources', ['vim-lsp', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'])
endif
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy'],
      \   'sorters': ['sorter_rank'],
      \   'converters': ['converter_remove_overlap', 'converter_truncate'],
      \ },
      \ 'around': {'mark': 'A'},
      \ 'dictionary': {'matchers': ['matcher_editdistance'], 'sorters': [], 'maxCandidates': 6, 'mark': 'D', 'minAutoCompleteLength': 3},
      \ 'necovim': {'mark': 'neco'},
      \ 'nvim-lsp': {'mark': 'lsp', 'forceCompletionPattern': "\\.|:\\s*|->", 'ignoreCase': v:true},
      \ 'ddc-vim-lsp': {'mark': 'lsp', 'forceCompletionPattern': "\\.|:\\s*|->", 'ignoreCase': v:true},
      \ 'buffer': {'mark': 'B', 'ignoreCase': v:true},
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
      \ 'buffer': {'forceCollect': v:true, 'fromAltBuf': v:true},
      \ 'dictionary': {'smartCase': v:true, 'showMenu': v:false},
      \ })
call ddc#custom#patch_global('filterParams', {
      \ 'matcher_fuzzy': {'camelcase': v:true},
      \ 'converter_truncate': {'maxAbbrWidth': 60, 'maxInfo': 500, 'ellipsis': '...'},
      \ })

call ddc#custom#patch_global('specialBufferCompletion', v:true)
call ddc#custom#patch_filetype(
      \ ['denite-filter', 'TelescopePrompt'], 'specialBufferCompletion', v:false
      \ )

call ddc#custom#patch_filetype(['vim', 'toml'], {
      \ 'sources': ['necovim', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'],
      \ })
call ddc#custom#patch_filetype(
      \ ['zsh'], 'sources', ['zsh']
      \ )
call ddc#custom#patch_filetype(['zsh'], 'sourceOptions', {
      \ 'zsh': {'mark': 'Z'},
      \ })

autocmd User PumCompleteDone call vsnip_integ#on_complete_done(g:pum#completed_item)

call ddc#enable()
