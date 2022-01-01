function! vimrc#on_insert_enter() abort
  if !exists('b:win_ime_con_is_insert')
    return
  endif
  if b:win_ime_con_is_insert == 0
    if b:win_ime_con_is_active == 1
      call _activate_ime()
    endif
    let b:win_ime_con_is_insert = 1
  endif
endfunction

function! vimrc#disable_ime() abort
  if !exists('b:win_ime_con_is_insert')
    return
  endif
  if b:win_ime_con_is_insert
    call _disable_ime(v:true)
  else
    call _disable_ime(v:false)
  endif
  let b:win_ime_con_is_insert = 0
endfunction

function! vimrc#is_wsl() abort
  if !exists('g:vimrc_is_wsl')
    let g:vimrc_is_wsl = isdirectory('/mnt/c') && executable('/mnt/c/Windows/System32/cmd.exe')
  endif
  return g:vimrc_is_wsl
endfunction

function! vimrc#is_windows() abort
  if !exists('g:vimrc_is_windows')
    let g:vimrc_is_windows = has('win32') || has('win64')
  endif
  return g:vimrc_is_windows
endfunction

function! vimrc#on_filetype() abort
  if execute('filetype') =~# 'OFF'
    " Lazy loading
    silent! filetype plugin indent on
    syntax enable
    filetype detect
    call vimrc#color_settings()
  endif
endfunction

" additional settings for colorscheme
function! vimrc#color_settings() abort
  let cs = execute('colorscheme')
  if cs =~# 'iceberg'
    hi TabLineSel guifg=#ffffff
    hi clear TabLineFill
    hi TabLineFill guifg=#525252 guibg=#161821
    hi clear MatchParen
    hi MatchParen cterm=underline gui=underline
    hi EndOfBuffer guifg=#454545
    hi! link SignColumn Normal
    hi LspSignatureActiveParameter gui=underline
    hi LspReferenceRead gui = underline
    hi LspReferenceText gui = underline
    hi LspReferenceWrite gui=underline
    hi! link TSProperty Statement
    if has('nvim')
      highlight DdcNvimLspDocBorder blend=30 guifg=#c6c8d1 guibg=#3d425b
    endif
  elseif cs =~# 'shirotelin'
    hi clear TabLineFill
    hi TabLineFill guifg=#999999
    hi! link Pmenu FloatWindow
    hi DiffAdd term=NONE cterm=NONE ctermbg=194 guibg=#C8FFC8
    hi DiffRemoved term=NONE cterm=NONE ctermbg=224 gui=NONE guibg=#FFC8C8
    hi! link diffAdded DiffAdd
    hi! link diffRemoved DiffRemoved
  endif
endfunction
