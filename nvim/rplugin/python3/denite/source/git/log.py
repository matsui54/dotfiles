import subprocess

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates
from denite.base.kind import Base as KindBase

GITLOG_OBJ_SYNTAX = (
    'syntax match {0}_obj '
    r'/^\s\S*/ '
)

GITLOG_OBJ_HIGHLIGHT = (
    'highlight default link {0}_obj Statement'
)


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "git/log"
        self.kind = Kind(vim)

    def highlight(self) -> None:
        self.vim.command(GITLOG_OBJ_SYNTAX.format(self.syntax_name))
        self.vim.command(GITLOG_OBJ_HIGHLIGHT.format(self.syntax_name))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        cwd = self.vim.call('getcwd')
        output = subprocess.run(['git', 'log', '--pretty=oneline',
                                 '--abbrev-commit', '--', '.'],
                                stdout=subprocess.PIPE, cwd=cwd)
        items = output.stdout.decode().split('\n')
        if not items:
            return []
        for item in items:
            candidates.append(
                {
                    "word": item,
                    "__obj": item.split(' ')[0],
                }
            )
        return candidates


class Kind(KindBase):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)

        self.name = 'gitdiff'

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]

        diff_cmd = ['git', 'diff', target['__obj'] + '^!']

        self.preview_terminal(context, diff_cmd, 'preview')
