import linecache

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates

SYMBOLS_HIGHLIGHT_SYNTAX = [
    {'name': 'Name', 'link': 'Constant',  're': r'\%(\] \zs\)\@<=\S*'},
    {'name': 'Type', 'link': 'Function',  're': r'\[\a\+\]'},
    # {'name': 'Pos', 'link': 'Statement', 're': r'\s*\d\+\s\+\d\+\s\@=\['},
]


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "lsp/document_symbol"
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
        items = self.vim.lua._lsp_denite.document_symbol()
        if not items:
            return []
        for item in items:
            path = item["filename"]
            col = item["col"]
            lnum = item["lnum"]
            line = linecache.getline(path, lnum)
            type, name = item["text"].split()
            word = "{:>4}{:>4} {} {}    {}".format(
                str(lnum), str(col), type, name, line
            )
            candidates.append(
                {
                    "word": word,
                    "action__path": path,
                    "action__line": lnum,
                    "action__col": col,
                }
            )
        return candidates
