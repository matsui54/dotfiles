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
      echo "  --system  : Also install minimal system packages (zsh, build tools, etc.) via apt/dnf and chsh"
      exit 1
      ;;
  esac
done

if [[ "$WITH_SYSTEM" == true ]]; then
  if command -v apt-get >/dev/null 2>&1; then
    echo "==> Installing minimal system packages via apt..."
    sudo apt-get update
    sudo apt-get install -y zsh git build-essential locales cmake gettext ninja-build curl
    sudo locale-gen en_US.UTF-8
  elif command -v dnf >/dev/null 2>&1; then
    echo "==> Installing minimal system packages via dnf..."
    sudo dnf install -y zsh git gcc gcc-c++ make cmake gettext ninja-build curl glibc-langpack-en glibc-gconv-extra util-linux-user
  else
    echo "ERROR: Unsupported package manager (expected apt-get or dnf)." >&2
    exit 1
  fi
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
  if [[ -n "$ZSH_BIN" && "${SHELL:-}" != "$ZSH_BIN" ]]; then
    if command -v chsh >/dev/null 2>&1; then
      echo "==> Changing default shell to $ZSH_BIN..."
      chsh -s "$ZSH_BIN"
    else
      echo "WARNING: chsh not found; please change your default shell to $ZSH_BIN manually." >&2
    fi
  fi
fi

echo "==> Setup complete!"

