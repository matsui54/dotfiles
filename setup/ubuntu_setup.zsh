#!/bin/zsh

echo "source zshrc/zshenv? (y/N): "
if read -q; then
  source ~/.zshrc
  source ~/.zshenv
else
  echo "skip"
fi

if [[ -x $(which go) && ! -x $(which ghq) ]]; then
  echo "install ghq? (y/N): "
  if read -q; then
    go install github.com/x-motemen/ghq@latest
cat <<EOF >> ~/.gitconfig
[ghq]
  root = ~/.cache/dein/repos/
  root = ~/ghq/
EOF
  else
    echo "skip"
  fi
fi

if [[ ! -x $(which nvim) && -x $(which ghq) ]]; then
  echo "install nvim? (y/N): "
  if read -q; then
    sudo apt-get install ninja-build gettext libtool libtool-bin autoconf automake cmake g++ pkg-config unzip curl doxygen
    ghq get -l git@github.com:neovim/neovim.git
    make CMAKE_BUILD_TYPE=Release
    sudo make install
  else
    echo "skip"
  fi
fi

if [[ ! -s "$NVM_DIR/nvm.sh" ]]; then
  echo "install nvim? (y/N): "
  if read -q; then
    curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.1/install.sh | bash
    source ~/.zshenv
  else
    echo "skip"
  fi
fi
