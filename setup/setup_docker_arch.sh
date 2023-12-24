#!/usr/bin/env bash

set -eu

install_packages ()
{
  PACKAGES=(zsh zsh-syntax-highlighting \
    ripgrep bat fzf fd bottom htop dust duf \
    nodejs npm go zip deno rust cargo \
    wget man-db unzip openssh pyenv \
    words skk-jisyo \
    base-devel cmake unzip ninja curl \
    sshfs vim rclone pacman-contrib ctags \
    reflector parallel tmux clang boost python-pip \
  )
  sudo pacman --noconfirm -Syu --needed ${PACKAGES[*]}
}

install_dotfiles ()
{
  if [[ ! -d $HOME/dotfiles ]]; then
    git clone https://github.com/matsui54/dotfiles.git ~/dotfiles
  fi
  Dotdir=$HOME/dotfiles $HOME/dotfiles/setup/install_dot
  # pushd $HOME/dotfiles
  #   git remote set-url origin git@github.com:matsui54/dotfiles.git
  # popd
}

chsh_to_zsh ()
{
  ZSH_BIN=/bin/zsh
  if [[ -x "$ZSH_BIN" && $SHELL != "$ZSH_BIN" ]]; then
    echo "change shell to zsh"
    sudo chsh -s "$ZSH_BIN" "$(id un)"
  fi
}

install_pyenv ()
{
  if [[ $(pyenv version-name) == "system" ]]; then
    sudo pacman --noconfirm -S --needed base-devel openssl zlib xz tk
    set +e
    pyenv install 3 && pyenv global $(pyenv latest 3)
    set -e
  fi
}

install_nvim ()
{
  if [[ ! -x $(which nvim) ]]; then
    git clone --depth 1 https://github.com/neovim/neovim.git $HOME/neovim
    if [[ ! -d $HOME/.local/bin ]]; then
      mkdir -p "$HOME/.local/bin"
    fi
    pushd "$HOME/neovim"
      make CMAKE_BUILD_TYPE=Release CMAKE_INSTALL_PREFIX=$HOME/.local/nvim install
      ln -s $HOME/.local/nvim/bin/nvim $HOME/.local/bin/nvim
    popd
  fi
}

setup_for_docker ()
{
  git clone https://github.com/woefe/git-prompt.zsh.git $HOME/git-prompt.zsh
  sudo sed -i '/^#en_US.UTF-8 UTF-8/s/^#//' /etc/locale.gen
  sudo locale-gen
  pip install plotly polars matplotlib
}

install_packages
install_dotfiles
chsh_to_zsh
install_pyenv
install_nvim
setup_for_docker
echo "done"
