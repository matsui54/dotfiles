import subprocess
from pathlib import Path

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
        gitdir = run_command(
            self.vim, ['git', 'rev-parse', '--show-toplevel'])[0]
        format = r'%h %s %cr <%an>%d'
        items = run_command(self.vim, [
            'git', 'log',
            f'--pretty=format:{format}', '--abbrev-commit', '--', '.'
        ], cwd=gitdir)
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
        self.default_action = 'open'

    def action_open(self, context: UserContext) -> None:
        target = context['targets'][0]
        self.vim.command("Gina show {}".format(target['__obj']))

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]

        format = ("commit %H%nparent %P%nauthor %an <%ae> %ad%ncommitter %cn "
                  "<%ce> %cd%n %e%n%n%s%n%n%b")

        gitdir = (Path(run_command(self.vim,
                                   ['git', 'rev-parse', '--show-toplevel'])[0])
                  .joinpath('.git'))

        cmds = ['git', '--no-pager', '--git-dir=' + str(gitdir), 'show',
                f'--pretty=format:{format}', target['__obj'], '--']
        # diff_cmd = ['git', 'diff', target['__obj'] + '^!']

        self.preview_terminal(context, cmds, 'preview')


def run_command(vim: Nvim, cmd, cwd=''):
    if not cwd:
        cwd = vim.call('getcwd')
    output = subprocess.run(cmd, stdout=subprocess.PIPE, cwd=cwd)
    return output.stdout.decode().split('\n')
