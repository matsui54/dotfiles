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
  call pum#set_option('highlight_normal_menu', 'FloatWindow')
  " autocmd User PumCompleteDone call vsnip_integ#on_complete_done(g:pum#completed_item)

  " command line completion
  if v:true
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
      " if getcmdtype() == '@'
      "   return
      " end

      " Overwrite sources
      let current = ddc#custom#get_current()
      if index(current.sources, 'cmdline-history') == -1
        let s:prev_buffer_sources = current
      endif
      if getcmdtype() == '/'
        call ddc#custom#patch_buffer('sources', ['cmdline-history', 'buffer'])
      elseif getcmdtype() == '@'
        call ddc#custom#patch_buffer('sources', ['buffer'])
      else
        call ddc#custom#patch_buffer('sources', ['cmdline', 'cmdline-history', 'buffer'])
      endif

      " Enable command line completion
      call ddc#enable_cmdline_completion()
    endfunction
    function! CommandlinePost() abort
      " Restore sources
      call ddc#custom#set_buffer(s:prev_buffer_sources)
    endfunction
  endif
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
call ddc#custom#patch_global('keywordPattern', "[-\\w]+")
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
      \   'matchers': ['matcher_fuzzy'],
      \   'sorters': ['sorter_fuzzy'],
      \   'converters': ['converter_remove_overlap', 'converter_truncate', 'converter_fuzzy'],
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
      \   'maxCandidates': 6,
      \   'mark': 'D', 
      \   'minAutoCompleteLength': 3,
      \ },
      \ 'necovim': {'mark': 'neco', 'maxCandidates': 6},
      \ 'nvim-lsp': {
      \   'mark': 'lsp', 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \   'ignoreCase': v:true
      \ },
      \ 'vim-lsp': {
      \   'mark': 'lsp', 
      \   'forceCompletionPattern': "\\.|:\\s*|->", 
      \   'ignoreCase': v:true
      \ },
      \ 'buffer': {'mark': 'B', 'maxCandidates': 10, 'ignoreCase': v:true},
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
      \ 'buffer': {'forceCollect': v:true, 'fromAltBuf': v:true, 'showBufName': v:true},
      \ 'dictionary': {'smartCase': v:true, 'showMenu': v:false},
      \ })
call ddc#custom#patch_global('filterParams', {
      \ 'converter_truncate': {'maxAbbrWidth': 60, 'maxInfo': 500, 'ellipsis': '...'},
      \ 'converter_fuzzy': {'hlGroup': 'Title'},
      \ })

call ddc#custom#patch_global('specialBufferCompletion', v:true)
call ddc#custom#patch_filetype(
      \ ['denite-filter', 'TelescopePrompt'], 'specialBufferCompletion', v:false
      \ )

call ddc#custom#patch_filetype(['toml'], {
      \ 'sources': ['necovim', 'skkeleton', 'buffer', 'around', 'vsnip', 'file', 'dictionary'],
      \ })
" include @ for snippet
call ddc#custom#patch_filetype(
      \ ['tex'], 'keywordPattern', '[a-zA-Z0-9_@]*'
      \ )
call ddc#custom#patch_filetype(['zsh'], 'sourceOptions', {
      \ 'zsh': {'mark': 'Z'},
      \ })

call ddc#enable()

augroup gh_autocmd
  au!
  autocmd User gh_open_issue call EnableAutoCompletion()
augroup END

function! EnableAutoCompletion() abort
  " Enable source 'gh_issues' to current buffer.
  call ddc#custom#patch_buffer('sources', ['gh_issues'])
  call ddc#custom#patch_buffer('sourceOptions', {
        \ 'gh_issues': {
          \  'matcherKey': 'menu'
        \ }})
endfunction
