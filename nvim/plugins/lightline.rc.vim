let g:lightline = {}
let g:lightline.active = {'left': [ ['mode', 'paste'], ['readonly'], ['relativepath'] ]}
let g:lightline.colorscheme = 'iceberg'
let g:lightline.enable = {
      \ 'statusline': 1,
      \ 'tabline': 0
      \ }
let g:lightline.separator = { 'left': '', 'right': '' }
let g:lightline.subseparator = { 'left': '|', 'right': '|' }
let g:lightline.component = {
      \ 'lineinfo': '%3l/%L:%-2c'
      \ }
