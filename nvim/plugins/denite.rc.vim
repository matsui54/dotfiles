" Define mappings
autocmd MyAutoCmd FileType denite call s:denite_my_settings()
function! s:denite_my_settings() abort
  nnoremap <silent><buffer><expr> <CR>
        \ denite#do_map('do_action')
  nnoremap <silent><buffer><expr><nowait> d
        \ denite#do_map('do_action', 'delete')
  nnoremap <silent><buffer><expr> p
        \ denite#do_map('do_action', 'preview')
  nnoremap <silent><buffer><expr> P
        \ denite#do_map('do_action', 'preview_bat')
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

" autocmd MyAutoCmd User denite-preview call s:denite_preview()
" function! s:denite_preview() abort
"   ALEDisableBuffer
" endfunction

autocmd MyAutoCmd FileType denite-filter call s:denite_filter_my_settings()
function! s:denite_filter_my_settings() abort
  call deoplete#custom#buffer_option('auto_complete', v:false)
  imap <silent><buffer> <C-o> <Plug>(denite_filter_quit)
  imap <silent><buffer> <C-c> <Plug>(denite_filter_quit)
  inoremap <silent><buffer><expr> <Tab>
        \ denite#increment_parent_cursor(1)
  inoremap <silent><buffer><expr> <S-Tab>
        \ denite#increment_parent_cursor(-1)
  nnoremap <silent><buffer><expr> <C-j>
        \ denite#increment_parent_cursor(1)
  nnoremap <silent><buffer><expr> <C-k>
        \ denite#increment_parent_cursor(-1)
  " imap <silent><buffer> <CR> <C-o><CR>
endfunction

call denite#custom#option('default', {
      \ 'preview_height': 20,
      \ 'auto_resize': v:true,
      \})

function! s:jump_defx(context) abort
  let path = a:context.targets[0].action__path
  execute "Defx -buffer-name=`t:defx_index` " . path
endfunction
call denite#custom#action('directory', 'jump_defx',
      \ function('s:jump_defx'))

let s:fd_cmds = ['fdfind', '.', '-H', '-E', '.git', '-E', '__pycache__', '-t']
" For ripgrep
if executable('fdfind')
  call denite#custom#var('file/rec', 'command', s:fd_cmds + ['f'])
  call denite#custom#var('directory_rec', 'command', s:fd_cmds + ['d'])
elseif executable('rg')
  call denite#custom#var('file/rec', 'command',
        \ ['rg', '--files', '--glob', '!.git', '--color', 'never'])
endif

" Change default action.
call denite#custom#source('directory_rec', 'default_action', 'cd')

" Ripgrep command on grep source
call denite#custom#var('grep', {
      \ 'command': ['rg'],
      \ 'default_opts': ['-i', '--vimgrep', '--no-heading'],
      \ 'recursive_opts': [],
      \ 'pattern_opt': ['--regexp'],
      \ 'separator': ['--'],
      \ 'final_opts': [],
      \ })

" Specify multiple paths in grep source
"call denite#start([{'name': 'grep',
"      \ 'args': [['a.vim', 'b.vim'], '', 'pattern']}])

" Define alias
call denite#custom#alias('source', 'file/rec/git', 'file/rec')
call denite#custom#var('file/rec/git', 'command',
      \ ['git', 'ls-files', '-co', '--exclude-standard'])
