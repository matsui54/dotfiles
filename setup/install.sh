#!/usr/bin/env bash
set -eu

DOTDIR="$(cd "$(dirname "$0")/.." && pwd)"
WITH_SYSTEM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system)
      WITH_SYSTEM=true
      shift
      ;;
    *)
      echo "Usage: $0 [--system]"
      echo "  (default) : Rootless setup (symlinks + ~/.zsh plugins + ~/.local binaries)"
      echo "  --system  : Also install minimal apt packages (zsh, build-essential) and chsh"
      exit 1
      ;;
  esac
done

if [[ "$WITH_SYSTEM" == true ]]; then
  echo "==> Installing minimal system packages via apt..."
  sudo apt update
  sudo apt install -y zsh build-essential locales cmake gettext ninja-build
  sudo locale-gen en_US.UTF-8
fi

echo "==> Linking dotfiles..."
Dotdir="$DOTDIR" "$DOTDIR/setup/install_dot"

echo "==> Setting up Zsh plugins in ~/.zsh..."
mkdir -p "$HOME/.zsh"
if [[ ! -d "$HOME/.zsh/zsh-syntax-highlighting" ]]; then
  git clone --depth=1 https://github.com/zsh-users/zsh-syntax-highlighting.git "$HOME/.zsh/zsh-syntax-highlighting"
fi
if [[ ! -d "$HOME/.zsh/git-prompt.zsh" ]]; then
  git clone --depth=1 https://github.com/woefe/git-prompt.zsh.git "$HOME/.zsh/git-prompt.zsh"
fi

echo "==> Installing user-space tools via pkg.py..."
python3 "$DOTDIR/scripts/pkg.py" install

if [[ "$WITH_SYSTEM" == true ]]; then
  ZSH_BIN="$(command -v zsh || true)"
  if [[ -n "$ZSH_BIN" && "$SHELL" != "$ZSH_BIN" ]]; then
    echo "==> Changing default shell to $ZSH_BIN..."
    chsh -s "$ZSH_BIN"
  fi
fi

echo "==> Setup complete!"

