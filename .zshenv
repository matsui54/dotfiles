typeset -U path PATH
path=(
  "$HOME/.local/bin"
  "$HOME/go/bin"
  "$HOME/.cargo/bin"
  $path
)
export PATH

if [[ -s "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi

export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
