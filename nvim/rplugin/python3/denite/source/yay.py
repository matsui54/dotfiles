import subprocess
import re

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates
from denite.kind.command import Kind as Command


MAN_ITEM_SYNTAX = (
    'syntax match {0}_obj '
    r'/\s*\S*\s(\d)/ '
)

MAN_ITEM_HIGHLIGHT = (
    'highlight default link {0}_obj Statement'
)


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "yay"
        self.kind = Kind(vim)

    def highlight(self) -> None:
        self.vim.command(MAN_ITEM_SYNTAX.format(self.syntax_name))
        self.vim.command(MAN_ITEM_HIGHLIGHT.format(self.syntax_name))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        output = subprocess.run(
            ['yay', '-Ssq'],
            stdout=subprocess.PIPE)
        items = output.stdout.decode().split('\n')
        if not items:
            return []
        for item in items:
            if not item:
                continue
            candidates.append(
                {
                    "word": item,
                    "abbr": item,
                    # "action__command": 'Man {}'.format(page + section),
                }
            )
        return candidates


class Kind(Command):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)

        self.name = 'yay'

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]
        man_cmd = ['yay', '-Sii', target['word']]

        self.preview_terminal(context, man_cmd, 'preview')
