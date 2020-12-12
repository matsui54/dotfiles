from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "document_symbol"
        self.kind = 'file'
        vim.exec_lua("_lsp_denite = require'lsp_denite'")

    # def highlight(self):
    #     self.vim.command(
    #         r"highlight default link deniteSource__UltisnipsPath Comment")
    #     self.vim.command(
    #         r"highlight default link deniteSource__UltisnipsTrigger Identifier"
    #     )
    #     self.vim.command(
    #         r"highlight default link deniteSource__UltisnipsDescription Statement"
    #     )

    # def define_syntax(self):
    #     self.vim.command("syntax case ignore")
    #     self.vim.command(
    #         r"syntax match deniteSource__UltisnipsHeader /^.*$/ "
    #         r"containedin=" + self.syntax_name
    #     )
    #     self.vim.command(
    #         r"syntax match deniteSource__UltisnipsPath /[^ ]\+$/ contained "
    #         r"containedin=deniteSource__UltisnipsHeader"
    #     )
    #     self.vim.command(
    #         r"syntax match deniteSource__UltisnipsTrigger /^.*\%20c/ contained "
    #         r"containedin=deniteSource__UltisnipsHeader"
    #     )
    #     self.vim.command(
    #         r"syntax match deniteSource__UltisnipsDescription /\%22c.*  / contained "
    #         r"containedin=deniteSource__UltisnipsHeader"
    #     )

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        items = self.vim.lua._lsp_denite.document_symbol()
        if not items:
            return []
        for item in items:
            col = item['col']
            lnum = item['lnum']
            text = item['text']
            candidates.append(
                {
                    "word": "{}".format(text + ':' + str(lnum) + ':' + str(col)),
                    "action__path": item['filename'],
                    "action__line": lnum,
                    "action__col": col,
                }
            )
        return candidates
