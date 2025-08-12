function! vimrc#is_wsl() abort
  if !exists('s:is_wsl')
    let s:is_wsl = filereadable('/proc/version') &&
    \ get(readfile('/proc/version', 'b', 1), 0, '') =~? 'microsoft'
  endif
  return s:is_wsl
endfunction

function! vimrc#denops_log(arg) abort
  call denops#notify('my_echo', 'echo', [a:arg])
endfunction

function! vimrc#is_windows() abort
  if !exists('s:is_windows')
    let s:is_windows = has('win32') || has('win64')
  endif
  return s:is_windows
endfunction

function vimrc#on_filetype() abort
  if &l:filetype ==# '' && &l:syntax ==# '' && line('$') < 10000
    " NOTE: filetype detect does not work on startup
    silent filetype detect

    if has('nvim') && bufnr()->bufloaded()
      lua <<END
      if vim.treesitter.get_parser(nil, nil, { error = false }) then
        vim.treesitter.start()
      else
        vim.cmd('syntax enable')
      end
END
    else
      syntax enable
    endif
  endif
endfunction

" additional settings for colorscheme
function! vimrc#color_settings(cs) abort
  if a:cs =~# 'iceberg'
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
  elseif a:cs =~# 'shirotelin'
    hi Special term=bold cterm=bold ctermfg=127 gui=bold guifg=#9425a8
    hi SpecialChar term=bold cterm=bold ctermfg=127 gui=bold guifg=#9425a8
    hi Tag term=bold cterm=bold ctermfg=127 gui=bold guifg=#9425a8
    hi Delimiter term=bold cterm=bold ctermfg=127 gui=bold guifg=#9425a8

    hi clear TabLineFill
    hi TabLineFill guifg=#999999
    " hi! link Pmenu FloatWindow
    hi DiffAdd term=NONE cterm=NONE ctermbg=194 guibg=#C8FFC8
    hi DiffRemoved term=NONE cterm=NONE ctermbg=224 gui=NONE guibg=#FFC8C8
    hi LspSignatureActiveParameter gui=underline
    hi! link @text.diff.add DiffAdd
    hi! link @text.diff.delete DiffRemoved
    hi! link diffAdded DiffAdd
    hi! link diffRemoved DiffRemoved
    hi! link LspReferenceRead ReferenceHighlight
    hi! link LspReferenceText ReferenceHighlight
    hi! link LspReferenceWrite ReferenceHighlight
    hi! link FloatBorder NormalFloat
  endif
endfunction
