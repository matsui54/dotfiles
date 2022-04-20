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

# enable color support of ls and also add handy aliases
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# ls aliases
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'

# git alias
alias ga='git add'
alias gc='git commit'
alias gp='git push'

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
eval "$(dircolors -b)"
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

# load xkb config
# if [ -f $HOME/.xkb/keymap/mykbd ]; then
#   xkbcomp -I$HOME/.xkb ~/.xkb/keymap/mykbd $DISPLAY 2> /dev/null
# fi

export LESS_TERMCAP_mb=$'\e[1;32m'
export LESS_TERMCAP_md=$'\e[1;32m'
export LESS_TERMCAP_me=$'\e[0m'
export LESS_TERMCAP_se=$'\e[0m'
export LESS_TERMCAP_so=$'\e[01;33m'
export LESS_TERMCAP_ue=$'\e[0m'
export LESS_TERMCAP_us=$'\e[1;4;31m'

# if wsl
if [ -d /mnt/c/Users/harum ]; then
  export WIN_HOME=/mnt/c/Users/harum
fi

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
  # Append this line to ~/.zshrc to enable fzf keybindings for Zsh:
  source /usr/share/doc/fzf/examples/key-bindings.zsh
  # Append this line to ~/.zshrc to enable fuzzy auto-completion for Zsh:
  source /usr/share/doc/fzf/examples/completion.zsh
fi

if [ -d ~/.zsh/zsh-syntax-highlighting ]; then
  source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi

if [ -f ~/.zsh/powerlevel10k/powerlevel10k.zsh-theme ]; then
  source ~/.zsh/powerlevel10k/powerlevel10k.zsh-theme
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
