from pathlib import Path

from denite.base.source import Base
from denite.util import globruntime, Nvim, UserContext, Candidates
from denite.base.kind import Kind as BaseKind

SESSION_OPTION_TABLE = {
    'default': 'blank,buffers,curdir,folds,help,tabpages,winsize',
    'blank': 'empty windows',
    'buffers': 'hidden and unloaded buffers, not just those in windows',
    'curdir': 'the current directory',
    'folds': 'manually created folds, opened/closed folds and local fold options',
    'globals': ('global variables that start with an uppercase letter and '
                'contain at least one lowercase letter. Only String and Number types are stored.'),
    'help': 'the help window',
    'localoptions': 'options and mappings local to a window or buffer ',
    'options': 'all options and mappings',
    'resize': "size of the Vim window: 'lines' and 'columns'",
    'tabpages': 'all tab pages; without this only the current tab page is restored.',
    'terminal': 'include terminal windows where the command can be restored',
    'winpos': 'position of the whole Vim window',
    'winsize': 'window sizes',
}


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "mksession"
        self.kind = Kind(vim)

    def gather_candidates(self, context):
        candidates = []

        for option in SESSION_OPTION_TABLE.keys():
            candidates.append(
                {
                    "word": "{}   {}".format(
                        option, SESSION_OPTION_TABLE[option]),
                    "__opt": option,
                }
            )
        return candidates


class Kind(BaseKind):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.name = "mksession"
        self.default_action = 'execute'

    def action_execute(self, context: UserContext) -> None:
        opts = []
        for target in context['targets']:
            if target['__opt'] == 'default':
                self._make_session()
                return
            opts.append(target['__opt'])
        prev_opts = self.vim.options['sessionoptions']
        self.vim.command('set sessionoptions={}'.format(','.join(opts)))
        self._make_session()
        self.vim.command('set sessionoptions={}'.format(prev_opts))

    def _make_session(self):
        name = self.vim.call('input', 'session name? ')
        path = Path.home().joinpath('.vim/sessions').joinpath(name)
        if path.exists():
            choise = self.vim.call(
                'confirm', f'{str(path)} already exists. Overwrite?',
                "&Overwrite\n&Cancel")
            if choise == 2:
                return
        self.vim.command(f'mksession! {path}')
