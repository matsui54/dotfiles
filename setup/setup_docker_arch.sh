#!/usr/bin/env bash

set -eu

install_packages ()
{
  PACKAGES=(zsh zsh-syntax-highlighting \
    ripgrep bat fzf fd bottom htop dust duf \
    nodejs npm go zip deno rust cargo \
    wget man-db unzip openssh \
    words skk-jisyo \
    base-devel cmake unzip ninja curl \
    sshfs vim rclone pacman-contrib ctags \
    reflector parallel tmux \
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
    sudo chsh -s "$ZSH_BIN"
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
}

install_packages
install_dotfiles
chsh_to_zsh
install_nvim
setup_for_docker
echo "done"