inoremap <silent><expr> <TAB>
      \ pumvisible() ? "\<C-n>" : "\<TAB>"
inoremap <expr> <S-Tab> pumvisible() ? "\<C-p>" : "\<S-Tab>"

call ddc#custom#patch_global('sources', ['nvimlsp', 'buffer', 'ultisnips', 'dictionary'])
call ddc#custom#patch_global('sourceOptions', {
      \ '_': {
        \   'matchers': ['matcher_fuzzy'],
        \   'sorters': ['sorter_rank'],
        \ },
        \ 'around': {'mark': 'A'},
        \ 'dictionary': {'matchers': ['matcher_editdistance'], 'sorters': [], 'maxCandidates': 6, 'mark': 'D', 'minAutoCompleteLength': 3},
        \ 'eskk': {'mark': 'eskk', 'matchers': [], 'sorters': []},
        \ 'necovim': {'mark': 'neco'},
        \ 'nvimlsp': {'mark': 'lsp', 'forceCompletionPattern': "\\.|:\\s*|->"},
        \ 'buffer': {'mark': 'B'},
        \ 'ultisnips': {'mark': 'US'},
        \ })
call ddc#custom#patch_global('sourceParams', {
      \ 'around': {'maxSize': 500},
      \ 'nvimlsp': {'useIcon': v:true},
      \ })
call ddc#custom#patch_global('filterParams', {
      \ 'matcher_fuzzy': {'camelcase': v:true},
      \ })
call ddc#custom#patch_global('specialBufferCompletionFiletypes', [
      \ 'gina-commit',
      \ ])

call ddc#custom#patch_filetype(['vim', 'toml'], {
      \ 'sources': ['necovim', 'buffer'],
      \ })
call ddc#custom#patch_filetype(
      \ ['zsh'], 'sources', ['zsh']
      \ )
call ddc#custom#patch_filetype(['zsh'], 'sourceOptions', {
      \ 'zsh': {'mark': 'Z'},
      \ })

call ddc#enable()
