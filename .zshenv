export DENO_INSTALL="$HOME/.deno"

export PATH=$HOME/.local/zig:$PATH
export PATH=$HOME/go/bin:$PATH
export PATH=/usr/local/go/bin:$PATH
export PATH=$DENO_INSTALL/bin:$PATH
export PATH=$HOME/.local/bin:$PATH
export PATH=$HOME/.local/julia/bin:$PATH

export PATH=/usr/local/texlive/2021/bin/x86_64-linux:$PATH
export PATH=/usr/local/texlive/2022/bin/x86_64-linux:$PATH

if [[ -s "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi
