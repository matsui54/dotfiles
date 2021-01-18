import pathlib

from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates
from denite.base.kind import Base as Command


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "gina/action"
        self.kind = Kind(vim)

    def gather_candidates(self, context):
        candidates = []
        vars = self.vim.call('getbufvar', '', '')
        actions = {}
        for var in vars.keys():
            if '_vital_action_binder_' in var:
                actions = vars[var]['actions']

        if actions is None:
            return []

        for action in actions.keys():
            candidates.append(
                {
                    "word": "{:<40}  {}"
                    .format(action, actions[action]['description']),
                    "__action": action,
                }
            )
        return sorted(candidates, key=lambda x: x['__action'])


class Kind(Command):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.name = "gina_action"
        self.default_action = 'command'

    def action_command(self, context: UserContext) -> None:
        self.vim.call('denite#call_map', 'quit')
        action = context["targets"][0]["__action"]
        self.vim.call('gina#action#call', action)
