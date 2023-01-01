let g:quickrun_config = {}
let g:quickrun_config._ = {}
if has('nvim')
  let g:quickrun_config._['runner'] = 'nvimterm'
endif

let g:quickrun_config['cpp'] = {
      \  'cmdopt' : '-std=c++2a -Wall',
      \  'outputter' : 'quickfix',
      \  'outputter/message/log' : 1
      \ }

let g:quickrun_config['cpp/compe'] = {
      \  'type': 'cpp/g++',
      \  'input' : 'in.dat',
      \  'runner' : 'system'
      \ }

let g:quickrun_config['vim'] = {
      \   'command': ':source',
      \   'exec': '%C %S',
      \   'hook/eval/template': 'echo %s',
      \   'runner': 'vimscript',
      \ }
let g:quickrun_config['lua'] = {
      \   'command': ':luafile',
      \   'exec': '%C %S',
      \   'runner': 'vimscript',
      \ }

let g:quickrun_config['typescript'] = {
      \   'type': 'typescript/deno'
      \ }

let g:quickrun_config['gnuplot'] = {
      \   'command': 'gnuplot',
      \   'exec': '%C %S',
      \ }

let g:quickrun_config['python/compe'] = {
      \  'type': 'python',
      \  'input' : 'in.dat',
      \  'runner' : 'system'
      \ }
