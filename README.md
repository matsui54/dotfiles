## dependencies
- create python venv
```
python -m venv ~/.vim/python3
source ~/.vim/python3/bin/activate
pip install -r ~/dotfiles/requirements.txt
```
- ripgrep
- bat
- fd
- clangd
- wsl-open(if wsl)
- SKK-JISYO.L(windows: ~/AppData/Local/skk/SKK-JISYO.L, linux: /usr/local/share/skk/SKK-JISYO.L)
``` bash
wget -P /tmp http://openlab.jp/skk/dic/SKK-JISYO.L.gz
gunzip /tmp/SKK-JISYO.L.gz
sudo mkdir /usr/local/share/skk
mv /tmp/SKK-JISYO.L /usr/local/share/skk
```
