import subprocess
from pathlib import Path
import re

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates
from denite.kind.directory import Kind as BaseKind


def _check_output(commands):
    output = subprocess.run(commands, stdout=subprocess.PIPE)
    return output.stdout.decode().split('\n')


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "ghq"
        self.kind = Kind(vim)

    def highlight(self) -> None:
        pass

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        if not self.vim.call('executable', 'ghq'):
            return []
        root = _check_output(['ghq', 'root'])[0]
        items= _check_output(['ghq', 'list'])
        if not items:
            return []
        for item in items:
            if not item:
                continue
            candidates.append(
                    {
                        "word": item,
                        "abbr": item,
                        "action__path": str(Path(root).joinpath(item)),
                        }
                    )
        return candidates

class Kind(BaseKind):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.name = 'ghq'
        self.default_action = 'cd'

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]
        ls_cmd = ['ls', target['action__path']]

        self.preview_terminal(context, ls_cmd, 'preview')
