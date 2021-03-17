from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates

TYPE_DIAGNOSTICS = {
    1: "Error",
    2: "Warning",
    3: "Information",
    4: "Hint"
}


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "lsp/diagnostic_buffer"
        self.kind = "file"
        vim.exec_lua("_lsp_denite = require'lsp_denite'")

    def highlight(self) -> None:
        for type in TYPE_DIAGNOSTICS.values():
            self.vim.command(
                r'syntax match {0}_{1} /{2}\s\d\+:\d\+/ '
                'contained containedin={0}'.format(
                    self.syntax_name, type, type[0]))
            self.vim.command(
                r'highlight default link {0}_{1} LspDiagnosticsSign{1}'.format(
                    self.syntax_name, type))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        items: list = self.vim.lua._lsp_denite.diagnostic_buffer()
        if not items:
            return []
        path = self.vim.call('expand', '%:p')
        for item in items:
            col = item["range"]["start"]["character"] + 1
            lnum = item["range"]["start"]["line"] + 1
            type = TYPE_DIAGNOSTICS[item['severity']]
            word = "{} {}:{}   {}".format(
                type[0], str(lnum), str(col), item["message"]
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
