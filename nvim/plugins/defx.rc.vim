autocmd FileType defx call s:defx_my_settings()

function! s:quick_view()
  let win = win_getid()
  call defx#call_action('drop')
  call win_gotoid(win)
endfunction
function! s:open_defx_in_tab()
  let dir = defx#get_candidate().action__path
  tabnew
  execute "normal \<C-f>"
  call defx#call_action('cd', [dir])
endfunction
function! s:switch_defx_win() abort
  for i in tabpagebuflist()
    if bufname(i) =~# '^\[defx]' &&
          \ i != bufnr('')
      call win_gotoid(win_findbuf(i)[0])
      return
    endif
  endfor
  :Defx -buffer-name=temp
endfunction
function! s:get_defx_cwd()
  return escape(fnamemodify(defx#get_candidate().action__path,':h:p'), ':\')
endfunction

function! s:defx_my_settings() abort
  setlocal cursorline

  " Define mappings
  nnoremap <silent><buffer><expr> <CR>
        \ defx#is_directory() ?
        \ defx#do_action('open_directory') :
        \ defx#do_action('multi', ['drop', 'quit'])
  nnoremap <silent><buffer><expr> c
        \ defx#do_action('copy')
  nnoremap <silent><buffer><expr> m
        \ defx#do_action('move')
  nnoremap <silent><buffer><expr> p
        \ defx#do_action('paste')
  nnoremap <silent><buffer><expr> l
        \ defx#is_directory() ?
        \ defx#do_action('open_directory') :
        \ ":call <SID>quick_view()<CR>"
  nnoremap <silent><buffer><expr> E
        \ defx#do_action('multi', [['open', 'vsplit'], 'quit'])
  nnoremap <silent><buffer><expr> P
        \ defx#do_action('preview')
  nnoremap <silent><buffer><expr> t
        \ defx#is_directory() ?
        \ ":call <SID>open_defx_in_tab()<CR>" :
        \ defx#do_action('open', 'tabnew')
  nnoremap <silent><buffer><expr> o
        \ defx#do_action('open_tree', 'toggle')
  nnoremap <silent><buffer><expr> O
        \ defx#async_action('open_tree', 'recursive')
  nnoremap <silent><buffer><expr> K
        \ defx#do_action('new_directory')
  nnoremap <silent><buffer><expr> N
        \ defx#do_action('new_file')
  nnoremap <silent><buffer><expr> M
        \ defx#do_action('new_multiple_files')
  nnoremap <silent><buffer><expr> S
        \ defx#do_action('multi', [['toggle_sort', 'time'], 'redraw'])
  nnoremap <silent><buffer><expr> d
        \ defx#do_action('remove_trash')
  nnoremap <silent><buffer><expr> r
        \ defx#do_action('rename')
  nnoremap <silent><buffer><expr> !
        \ defx#do_action('execute_command')
  nnoremap <silent><buffer><expr> x
        \ defx#do_action('execute_system')
  nnoremap <silent><buffer><expr> yy
        \ defx#do_action('yank_path')
  nnoremap <silent><buffer><expr> .
        \ defx#do_action('toggle_ignored_files')
  nnoremap <silent><buffer><expr> h
        \ defx#do_action('cd', ['..'])
  nnoremap <silent><buffer><expr> ~
        \ defx#do_action('cd')
  nnoremap <silent><buffer><expr> q
        \ defx#do_action('quit')
  nnoremap <silent><buffer><expr> <Esc>
        \ defx#do_action('quit')
  nnoremap <silent><buffer><expr> ,
        \ defx#do_action('toggle_select') . 'j'
  nnoremap <silent><buffer><expr> *
        \ defx#do_action('toggle_select_all')
  nnoremap <silent><buffer><expr> j
        \ line('.') == line('$') ? 'gg' : 'j'
  nnoremap <silent><buffer><expr> k
        \ line('.') == 1 ? 'G' : 'k'
  nnoremap <silent><buffer><expr> <C-l>
        \ defx#do_action('redraw') . ":nohlsearch<CR>"
  nnoremap <silent><buffer><expr> <C-g>
        \ defx#do_action('print')
  nnoremap <silent><buffer><expr> cd
        \ defx#do_action('change_vim_cwd')
  nnoremap <silent><buffer><expr> '
        \ defx#do_action('cd', [getcwd()])
  nnoremap <silent><buffer><expr> <TAB>
        \ winwidth(0) > 50 ? ":80 wincmd < <CR>" :
        \ ":80 wincmd > <CR>"
  nnoremap <silent><buffer> <Space><Tab>
        \ :call <SID>switch_defx_win()<CR>

  nnoremap <silent><buffer><expr> <Space>f 
        \ defx#do_action('cd', [expand('~/dotfiles/nvim')])
  nnoremap <silent><buffer><expr> <Space>w 
        \ defx#do_action('cd', [expand('~/work')])
  nnoremap <silent><buffer><expr> <Space>p 
        \ defx#do_action('cd', [expand('~/.cache/dein/repos/github.com')])

  nnoremap <silent><buffer><expr> <Space>g
        \ ":Denite grep:" . <SID>get_defx_cwd() . "<CR>"
  nnoremap <silent><buffer><expr> <Space>s
        \ ":Denite directory_rec:" . <SID>get_defx_cwd() . "<CR>"
  nnoremap <silent><buffer><expr> <Space><Space>
        \ ":Denite file/rec:" . <SID>get_defx_cwd() . "<CR>"
endfunction
