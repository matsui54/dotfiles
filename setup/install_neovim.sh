#!/bin/bash -eu

# 変数設定
DOWNLOAD_URL="https://github.com/neovim/neovim/releases/download/nightly/nvim-linux-x86_64.tar.gz"
DEST_DIR="$HOME/.local/nvim"
TEMP_DIR=$(mktemp -d)

# 必要なディレクトリを作成
mkdir -p "$DEST_DIR"

# ファイルをダウンロード
echo "Downloading Neovim from $DOWNLOAD_URL..."
curl -L "$DOWNLOAD_URL" -o "$TEMP_DIR/nvim-linux-x86_64.tar.gz"

# 解凍
echo "Extracting files to $DEST_DIR..."
tar -xzf "$TEMP_DIR/nvim-linux-x86_64.tar.gz" -C "$TEMP_DIR"

# ファイルを移動
mv "$TEMP_DIR/nvim-linux-x86_64/"* "$DEST_DIR"

# 一時ディレクトリを削除
rm -rf "$TEMP_DIR"

echo "Neovim has been installed to $DEST_DIR."
