import subprocess
from pathlib import Path

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates, abspath
from denite.kind.file import Kind as File

SYMBOLS_NR_SYNTAX = (
    'syntax match {0}_NR '
    r'/\d*\s*\d*/ '
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
        self.name = "git/status"
        self.kind = Kind(vim)

    def highlight(self) -> None:
        self.vim.command(SYMBOLS_NR_SYNTAX.format(self.syntax_name))
        self.vim.command(SYMBOLS_KIND_SYNTAX.format(self.syntax_name))
        self.vim.command(SYMBOLS_NAME_SYNTAX.format(self.syntax_name))
        # self.vim.command(SYMBOLS_NR_HIGHLIGHT.format(self.syntax_name))
        self.vim.command(SYMBOLS_KIND_HIGHLIGHT.format(self.syntax_name))
        self.vim.command(SYMBOLS_NAME_HIGHLIGHT.format(self.syntax_name))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        cwd = self.vim.call('getcwd')
        output = subprocess.run(['git', 'status', '-s', '--', '.'],
                                stdout=subprocess.PIPE, cwd=cwd)
        items = output.stdout.decode().split('\n')
        if not items:
            return []
        for item in items:
            if not item:
                continue
            # [mark, path] = item.split(' ')
            mark = item.split(' ')[-2]
            path = item.split(' ')[-1]
            candidates.append(
                {
                    "word": item,
                    "__mark": mark,
                    'action__path': abspath(self.vim, path),
                }
            )
        return candidates


class Kind(File):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)

        self.name = 'git/status'

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]
        diff_cmd = ['git', 'diff', target['action__path']]

        self.preview_terminal(context, diff_cmd, 'preview')
