import pathlib
from datetime import datetime

from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates
from denite.kind.command import Kind as Command


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "session"
        self.kind = Kind(vim)

    def highlight(self):
        self.vim.command(r"highlight default link deniteSource__SessionPath Statement")
        self.vim.command(
            r"highlight default link deniteSource__UpdateTime Identifier"
        )

    def define_syntax(self):
        self.vim.command("syntax case ignore")
        self.vim.command(
            r"syntax match deniteSource__SessionHeader /^.*$/ "
            r"containedin=" + self.syntax_name
        )
        self.vim.command(
            r"syntax match deniteSource__SessionPath /^.*\%50c/ contained "
            r"containedin=deniteSource__SessionHeader"
        )
        self.vim.command(
            r"syntax match deniteSource__UpdateTime /\%51c.*/ contained "
            r"containedin=deniteSource__SessionHeader"
        )

    def gather_candidates(self, context):
        candidates = []
        root = pathlib.Path.home().joinpath(".vim/sessions/")
        if not root.exists():
            return []
        for s_file in root.iterdir():
            date = datetime.fromtimestamp(s_file.stat().st_mtime)
            candidates.append(
                {
                    "word": "{:<80}{}".format(
                        s_file.name, date.strftime("%y.%m.%d %H:%M")
                    ),
                    "action__command": "source {}".format(str(s_file)),
                    "__path": s_file,
                }
            )
        return candidates


class Kind(Command):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)

        self.name = "session"
        self.redraw_actions = ['delete']
        self.persist_actions = ['delete']

    def action_edit(self, context: UserContext) -> None:
        return super().action_execute(context)

    def action_delete(self, context):
        for target in context["targets"]:
            target["__path"].unlink()
