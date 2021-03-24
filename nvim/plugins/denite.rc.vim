" Define mappings
autocmd MyAutoCmd FileType denite call s:denite_my_settings()
function! s:denite_my_settings() abort
  nnoremap <silent><buffer><expr> <CR>
        \ denite#do_map('do_action')
  nnoremap <silent><buffer><expr><nowait> d
        \ denite#do_map('do_action', 'delete')
  nnoremap <silent><buffer><expr> p
        \ denite#do_map('toggle_auto_action', 'preview')
  nnoremap <silent><buffer><expr> P
        \ denite#do_map('toggle_auto_action', 'preview_bat')
  nnoremap <silent><buffer><expr> H
        \ denite#do_map('toggle_auto_action', 'highlight')
  nnoremap <silent><buffer><expr> <C-f>
        \ denite#do_map('do_action', 'jump_defx')
  nnoremap <silent><buffer><expr> q
        \ denite#do_map('quit')
  nnoremap <silent><buffer><expr> i
        \ denite#do_map('open_filter_buffer')
  nnoremap <silent><buffer><expr> ,
        \ denite#do_map('toggle_select').'j'
  nnoremap <silent><buffer><expr> t
        \ denite#do_map('do_action', 'tabopen')
  nnoremap <silent><buffer><expr> E
        \ denite#do_map('do_action', 'vsplit')
  nnoremap <silent><buffer><expr> e
        \ denite#do_map('do_action', 'edit')

  nnoremap <buffer> <C-o> <Nop>
  nnoremap <buffer> <C-i> <Nop>
endfunction

autocmd MyAutoCmd FileType denite-filter call s:denite_filter_my_settings()
function! s:denite_filter_my_settings() abort
  imap <silent><buffer> <C-o> <Plug>(denite_filter_update)
  imap <silent><buffer> <C-c> <Plug>(denite_filter_quit)
endfunction

call denite#custom#option('default', {
      \ 'preview_height': 20,
      \ 'auto_resize': v:true,
      \})

call denite#custom#option('grep', {
      \ 'preview_height': 20,
      \ 'auto_resize': v:true,
      \ 'vertical_preview': v:true,
      \ 'winheight': 100,
      \ 'preview_width': 100,
      \})

function! s:jump_defx(context) abort
  let path = a:context.targets[0].action__path
  execute "Defx -buffer-name=defx`t:defx_index` " . path
endfunction
call denite#custom#action('directory', 'jump_defx',
      \ function('s:jump_defx'))

" For ripgrep
if executable('rg')
  call denite#custom#var('file/rec', 'command',
        \ ['rg', '--files', '--glob', '!.git', '--color', 'never'])
  call denite#custom#var('grep', {
        \ 'command': ['rg'],
        \ 'default_opts': ['-i', '--vimgrep', '--no-heading'],
        \ 'recursive_opts': [],
        \ 'pattern_opt': ['--regexp'],
        \ 'separator': ['--'],
        \ 'final_opts': [],
        \ })
endif

if executable('fd')
  let s:fd_cmds = 'fd'
  call extend(s:fd_cmds, ['.', '-H', '-E', '.git', '-E', '__pycache__', '-t'])
  call denite#custom#var('file/rec', 'command', s:fd_cmds + ['f'])
  call denite#custom#var('directory_rec', 'command', s:fd_cmds + ['d'])
endif

function! s:ts_preview(context) abort
  call luaeval('require("denite_ts_preview").show(_A)', a:context)
endfunction
call denite#custom#action('file', 'preview_ts',
      \ function('s:ts_preview'), {'is_quit': v:false})

" Change default action.
call denite#custom#source('directory_rec', 'default_action', 'cd')

" Define alias
call denite#custom#alias('source', 'file/rec/git', 'file/rec')
call denite#custom#var('file/rec/git', 'command',
      \ ['git', 'ls-files', '-co', '--exclude-standard'])
