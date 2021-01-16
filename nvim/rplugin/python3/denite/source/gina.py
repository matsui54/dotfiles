import pathlib

from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "gina"
        self.kind = "command"

    def gather_candidates(self, context):
        candidates = []
        suffix = 'autoload/gina/command/*.vim'
        command_names = []
        for rtp in self.vim.options['runtimepath'].split(','):
            paths = pathlib.Path(rtp).glob(suffix)
            command_names += [i.stem for i in paths]
        command_names = list(filter(lambda x: x[0] != '_', command_names))
        for name in sorted(command_names):
            candidates.append(
                {
                    "word": "{}".format(name),
                    "action__command": "Gina {}".format(name),
                }
            )
        return candidates
