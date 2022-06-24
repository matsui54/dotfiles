export DENO_INSTALL="$HOME/.deno"
export PATH=$HOME/.local/bin:$DENO_INSTALL/bin:/usr/local/go/bin:$HOME/go/bin:$PATH

export PATH=/usr/local/texlive/2021/bin/x86_64-linux:$PATH
export PATH=/usr/local/texlive/2022/bin/x86_64-linux:$PATH

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

if [[ -s "$HOME/.cargo/env" ]]; then
  source "$HOME/.cargo/env"
fi
