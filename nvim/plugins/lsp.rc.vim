" pip install python-language-server
let s:pyls_path = expand('~/.local/bin/pyls')
au User lsp_setup call lsp#register_server({
      \ 'name': 'pyls',
      \ 'cmd': {server_info->[s:pyls_path]},
      \ 'allowlist': ['python'],
      \ })
