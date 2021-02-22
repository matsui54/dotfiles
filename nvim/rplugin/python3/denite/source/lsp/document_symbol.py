import linecache

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates

SYMBOLS_NR_SYNTAX = (
    'syntax match {0}_NR '
    r'/^\d*\s*\d*/ '
    'nextgroup={0}_kind'
)
# SYMBOLS_NR_HIGHLIGHT = (
#     'highlight default link {0}_NR Statement'
# )

SYMBOLS_KIND_SYNTAX = (
    'syntax match {0}_kind '
    r'/\[\a\+\]/ '
    'nextgroup={0}_name contained skipwhite'
)
SYMBOLS_KIND_HIGHLIGHT = (
    'highlight default link {0}_kind Statement'
)

SYMBOLS_NAME_SYNTAX = (
    r'syntax match {0}_name /\S\+/ contained'
)
SYMBOLS_NAME_HIGHLIGHT = (
    'highlight default link {0}_name Constant'
)


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "lsp/document_symbol"
        self.kind = "file"
        vim.exec_lua("_lsp_denite = require'lsp_denite'")

    def highlight(self) -> None:
        self.vim.command(SYMBOLS_NR_SYNTAX.format(self.syntax_name))
        self.vim.command(SYMBOLS_KIND_SYNTAX.format(self.syntax_name))
        self.vim.command(SYMBOLS_NAME_SYNTAX.format(self.syntax_name))
        # self.vim.command(SYMBOLS_NR_HIGHLIGHT.format(self.syntax_name))
        self.vim.command(SYMBOLS_KIND_HIGHLIGHT.format(self.syntax_name))
        self.vim.command(SYMBOLS_NAME_HIGHLIGHT.format(self.syntax_name))

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
            # type, name = item["text"].split()
            word = "{:>4}{:>4} {}    {}".format(
                str(lnum), str(col), item["text"], line
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
