## dependencies
- ripgrep
- bat
- fd
- wsl-open(if wsl)
- deno
- node (using [nvm](https://github.com/nvm-sh/nvm))
- SKK-JISYO.L(windows: ~/AppData/Local/skk/SKK-JISYO.L, linux: /usr/local/share/skk/SKK-JISYO.L)

```bash
wget -P /tmp http://openlab.jp/skk/dic/SKK-JISYO.L.gz
sudo mkdir /usr/share/skk
gunzip /tmp/SKK-JISYO.L.gz -c | sudo tee /usr/share/skk/SKK-JISYO.L > /dev/null
```
