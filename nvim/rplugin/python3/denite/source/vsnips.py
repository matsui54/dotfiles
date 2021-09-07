from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates
from denite.kind.file import Kind as File


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "vsnips"
        self.kind = 'command'

    def highlight(self):
        self.vim.command(
            r"highlight default link deniteSource__UltisnipsPath Comment")
        self.vim.command(
            r"highlight default link deniteSource__UltisnipsTrigger Identifier"
        )
        self.vim.command(
            r"highlight default link deniteSource__UltisnipsDescription Statement"
        )

    def define_syntax(self):
        self.vim.command("syntax case ignore")
        self.vim.command(
            r"syntax match deniteSource__UltisnipsHeader /^.*$/ "
            r"containedin=" + self.syntax_name
        )
        self.vim.command(
            r"syntax match deniteSource__UltisnipsPath /[^ ]\+$/ contained "
            r"containedin=deniteSource__UltisnipsHeader"
        )
        self.vim.command(
            r"syntax match deniteSource__UltisnipsTrigger /^.*\%20c/ contained "
            r"containedin=deniteSource__UltisnipsHeader"
        )
        self.vim.command(
            r"syntax match deniteSource__UltisnipsDescription /\%22c.*  / contained "
            r"containedin=deniteSource__UltisnipsHeader"
        )

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        sources = self.vim.call("vsnip#source#find", self.vim.call("bufnr"))
        for source in sources:
            for snippet in source:
                for prefix in snippet['prefix']:
                    candidates.append(
                        {
                            "word": "{} {}"
                            .format(snippet['label'], snippet["description"]),
                            "abbr": "{:<20}{}   {}"
                            .format(prefix, snippet["description"], snippet['label']),
                            "source__trigger": prefix,
                        }
                    )
        return candidates
