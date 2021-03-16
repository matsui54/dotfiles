import linecache
from pathlib import Path

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates

SYMBOLS_HIGHLIGHT_SYNTAX = [
    {'name': 'File', 'link': 'Comment',   're': r'\S\+:\d\+:\d\+'},
]


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "lsp/references"
        self.kind = "file"
        vim.exec_lua("_lsp_denite = require'lsp_denite'")

    def highlight(self) -> None:
        for syn in SYMBOLS_HIGHLIGHT_SYNTAX:
            self.vim.command(
                'syntax match {0}_{1} /{2}/ contained containedin={0}'.format(
                    self.syntax_name, syn['name'], syn['re']))
            self.vim.command(
                'highlight default link {}_{} {}'.format(
                    self.syntax_name, syn['name'], syn['link']))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        items = self.vim.lua._lsp_denite.references()
        if items is None:
            return []

        buf_path = Path(self.vim.call('expand', '%:p'))
        cwd = self.vim.call('getcwd')
        for item in items:
            col = item["col"]
            lnum = item["lnum"]
            path = Path(item['filename'])
            if buf_path == path:
                name = path.name
                line = self.vim.call('getline', lnum)
            else:
                try:
                    name = path.relative_to(cwd)
                except ValueError:
                    name = str(path)
                line = linecache.getline(str(path), lnum)

            word = "{}:{}:{} {}".format(
                name, str(lnum), str(col), line
            )

            candidates.append(
                {
                    "word": word,
                    "action__path": str(path),
                    "action__line": lnum,
                    "action__col": col,
                }
            )
        return candidates
