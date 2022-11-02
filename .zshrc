# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Keep 1000 lines of history within the shell and save it to ~/.zsh_history:
HISTSIZE=5000
SAVEHIST=100000
HISTFILE=~/.zsh_history

EDITOR='nvim'

eval "$(dircolors -b)"
alias ls='ls --color=auto'

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

DIRSTACKSIZE=100
setopt auto_pushd
setopt pushd_minus
# .. -> 'cd ..'
setopt auto_cd
## Remove duplicate entries
setopt pushd_ignore_dups
## This reverts the +/- operators.
setopt pushd_to_home
# Ignore dups
setopt histignorealldups sharehistory
# Reduce spaces
setopt hist_reduce_blanks
# Ignore add history if space
setopt hist_ignore_space
setopt menu_complete

# Use modern completion system
autoload -Uz compinit
compinit

zstyle ':completion:*' auto-description 'specify: %d'
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' format 'Completing %d'
zstyle ':completion:*' group-name ''
zstyle ':completion:*' menu select interactive
zstyle ':completion:*:default' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' list-colors ''
zstyle ':completion:*' list-prompt %SAt %p: Hit TAB for more, or the character to insert%s
zstyle ':completion:*' matcher-list '' 'm:{a-z}={A-Z}' 'm:{a-zA-Z}={A-Za-z}' 'r:|[._-]=* r:|=* l:|=*'
zstyle ':completion:*' menu select=long
zstyle ':completion:*' select-prompt %SScrolling active: current selection at %p%s
zstyle ':completion:*' use-compctl false
zstyle ':completion:*' verbose true
zstyle ':completion:*:cd:*' ignore-parents parent pwd

zstyle ':completion:*:*:kill:*:processes' list-colors '=(#b) #([0-9]#)*=0=01;31'
zstyle ':completion:*:kill:*' command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'

export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# color settings (light)
export BAT_THEME='GitHub'
export FZF_DEFAULT_OPTS='--color=light'

# Use emacs keybindings even if our EDITOR is set to vi
bindkey -e

#visual editor
autoload -Uz edit-command-line; zle -N edit-command-line
bindkey "\C-x\C-e" edit-command-line

# Use vim keys in tab complete menu:
zmodload zsh/complist
bindkey -M menuselect 'h' vi-backward-char
bindkey -M menuselect 'k' vi-up-line-or-history
bindkey -M menuselect 'l' vi-forward-char
bindkey -M menuselect 'j' vi-down-line-or-history

function configure-vim() {
  ./configure --with-features=huge --enable-gui=gtk3 \
    --enable-python3interp \
    --enable-luainterp --with-luajit \
    --enable-fail-if-missing
}

function ghq-fzf() {
  local src=$(ghq list -p | fzf)
  if [ -n "$src" ]; then
    BUFFER="cd $src"
    # zle accept-line
    CURSOR=${#BUFFER}
  fi
  zle -R -c
}
zle -N ghq-fzf
bindkey '^]' ghq-fzf

if [ -d /usr/share/doc/fzf/examples ]; then
  source /usr/share/doc/fzf/examples/key-bindings.zsh
  source /usr/share/doc/fzf/examples/completion.zsh
elif [ -d /usr/share/fzf ]; then
  source /usr/share/fzf/completion.zsh
  source /usr/share/fzf/key-bindings.zsh
fi

if [ -d ~/.zsh/zsh-syntax-highlighting ]; then
  source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [ -f ~/.zsh/powerlevel10k/powerlevel10k.zsh-theme ]; then
  source ~/.zsh/powerlevel10k/powerlevel10k.zsh-theme
fi

export PYENV_ROOT="$HOME/.local/pyenv"
if [ -d $PYENV_ROOT ]; then
  command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"
  eval "$(pyenv init -)"
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
