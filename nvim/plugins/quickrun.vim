let g:quickrun_config = {}
let g:quickrun_config['cpp'] = {
			\  'command': 'g++',
			\  'cmdopt' : '-std=c++17 -Wall',
			\  'outputter' : 'quickfix',
			\  'outputter/message/log' : 1
			\}
let g:quickrun_config['python'] = {
			\  'command': 'python3',
			\  'outputter' : 'quickfix',
      \}
