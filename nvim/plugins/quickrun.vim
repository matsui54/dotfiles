let g:quickrun_config = {}
let g:quickrun_config['cpp'] = {
			\  'command': 'clang++',
			\  'cmdopt' : '-std=c++17 -Wall',
			\  'outputter' : 'message',
			\  'outputter/message/log' : 1,
			\  'hook/time/enable' : 1
			\}
