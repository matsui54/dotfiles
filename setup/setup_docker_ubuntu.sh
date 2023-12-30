#!/usr/bin/env bash

set -eu

install_packages ()
{
  sudo apt install -y \
    zsh \
    zsh-syntax-highlighting \
    ripgrep \
    bat \
    fzf \
    fd-find \
    htop \
    vim \
    tmux \
    locales \
    curl
}

install_dotfiles ()
{
  git clone https://github.com/matsui54/dotfiles.git ~/dotfiles
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
    sudo chsh -s "$ZSH_BIN" "$(id -un)"
  fi
}

install_nvim ()
{
  mkdir -p $HOME/.local/{bin,share,lib}
  wget https://github.com/neovim/neovim/releases/download/nightly/nvim-linux64.tar.gz
  tar -zxvf nvim-linux64.tar.gz
  mv nvim-linux64/bin/nvim $HOME/.local/bin/nvim
  mv nvim-linux64/lib/nvim $HOME/.local/lib/nvim
  mv nvim-linux64/share/nvim/ $HOME/.local/share/nvim
  rm -rf nvim-linux64
  rm nvim-linux64.tar.gz
}

setup_for_docker ()
{
  git clone https://github.com/woefe/git-prompt.zsh.git $HOME/git-prompt.zsh
  curl -fsSL https://deno.land/x/install/install.sh | sh
  sudo locale-gen en_US.UTF-8
}

install_packages
install_dotfiles
chsh_to_zsh
install_nvim
setup_for_docker
echo "done"
