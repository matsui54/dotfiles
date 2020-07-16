if has('gui_running')
  set guioptions-=tT
  set guioptions-=m
  set guioptions-=rL
  set guioptions-=e
endif

if has('vim_starting')
    " 挿入モード時に非点滅の縦棒タイプのカーソル
    let &t_SI .= "\e[6 q"
    " ノーマルモード時に非点滅のブロックタイプのカーソル
    let &t_EI .= "\e[2 q"
    " 置換モード時に非点滅の下線タイプのカーソル
    let &t_SR .= "\e[4 q"
endif

if filereadable(expand('~/.vim/colors/iceberg.vim'))
  colorscheme iceberg
endif

source ~/dotfiles/nvim/options.rc.vim
source ~/dotfiles/nvim/map.rc.vim

nnoremap <expr><F5> (&filetype=='vim') ? ":w <bar> :source %<CR>" 
			\: (&filetype=='python') ? ":wa <bar> :!python3 %" 
			\: ":wa"
