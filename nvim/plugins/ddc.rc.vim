inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

call ddc#custom#patch_global('sources', ['nvimlsp', 'eskk', 'buffer', 'dictionary'])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
        \   'matchers': ['matcher_fuzzy'],
        \   'sorters': ['sorter_rank'],
        \ },
        \ 'around': {'mark': 'A'},
        \ 'dictionary': {'maxCandidates': 8, 'mark': 'D', 'minAutoCompleteLength': 3},
        \ 'eskk': {'mark': 'eskk', 'matchers': [], 'sorters': []},
        \ 'necovim': {'mark': 'neco'},
        \ 'nvimlsp': {'mark': 'lsp', 'forceCompletionPattern': '\\.|:|->'},
        \ 'buffer': {'mark': 'B'},
        \ })
call ddc#custom#patch_global('sourceParams', {
      \ 'around': {'maxSize': 500},
      \ })
call ddc#custom#patch_global('filterParams', {
      \ 'matcher_fuzzy': {'camelcase': v:true},
      \ })

call ddc#custom#patch_filetype(['vim', 'toml'], {
      \ 'sources': ['buffer', 'necovim'],
      \ })
" call ddc#custom#patch_filetype(['vim', 'toml'], 'sourceOptions', {
"      \ 'neco': {'matchers': ['matcher_head']},
"        \ })
call ddc#custom#patch_filetype(
      \ ['denite-filter'], 'sources', ['around']
      \ )
call ddc#custom#patch_filetype(
      \ ['zsh'], 'sources', ['zsh']
      \ )
call ddc#custom#patch_filetype(['zsh'], 'sourceOptions', {
      \ 'zsh': {'mark': 'Z'},
      \ })

call ddc#enable()
