from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates
from denite.kind.file import Kind as File


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "document_symbol"
        self.kind = Kind(vim)
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
        # self.vim.exec_lua("_testplugin = require('testplugin')")
        candidates: Candidates = []
        # item = self.vim.lua._testplugin.add(2, 3)
        self.vim.lua._lsp_denite.document_symbol()
        items = self.vim.eval('b:document_symbols')
        for item in items:
            candidates.append(
                {
                    "word": "{}".format(item["text"]),
                }
            )
        return candidates
        # for key in items.keys():
        #     item = self.vim.vars["current_ulti_dict_info"][key]
        #     locs = item["location"].split(":")
        #     path = ":".join(locs[0:-1])
        #     line = locs[-1]
        #     candidates.append(
        #         {
        #             "word": "{} {}".format(key, item["description"]),
        #             "abbr": "{:<20}{}   {}".format(key, item["description"], path),
        #             "action__path": path,
        #             "action__line": line,
        #             "action__col": 0,
        #             "source__trigger": key,
        #             "__priority": 1 if item["description"] else 0,
        #         }
        #     )
        # return sorted(candidates, key=lambda x: x["__priority"], reverse=True)


class Kind(File):

    """ultisnips kind"""

    def __init__(self, vim):
        super().__init__(vim)
        self.default_action = "expand"
        self.name = "ultisnips"

    def action_expand(self, context):
        target = context["targets"][0]
        trigger = target["source__trigger"]
        self.vim.command("normal a{} ".format(trigger))
        self.vim.call("UltiSnips#ExpandSnippet")

    def action_edit(self, context):
        """
        edit snippet
        """
        self.action_open(context)
