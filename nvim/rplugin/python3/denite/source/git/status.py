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

        self.name = 'git'

    def action_preview(self, context: UserContext) -> None:
        target = context['targets'][0]

        if (self._previewed_target == target and
                context['auto_action'] == 'preview'):
            # Skip if auto_action
            return

        prev_id = self.vim.call('win_getid')
        is_nvim = self.vim.call('has', 'nvim')

        if self._previewed_winid:
            self.vim.call('win_gotoid', self._previewed_winid)
            if self.vim.call('win_getid') != prev_id:
                self.vim.command('bdelete! ' +
                                 str(self.vim.call('bufnr', '%')))
                self.vim.vars['denite#_previewing_bufnr'] = -1
            self.vim.call('win_gotoid', prev_id)
            self._previewed_winid = 0

            if self._previewed_target == target:
                # Close the window only
                return

        self.vim.call('denite#helper#preview_file', context, '')

        diff_cmd = ['git', 'diff', target['action__path']]

        if is_nvim:
            self.vim.call('termopen', diff_cmd)
        else:
            self.vim.call('term_start', diff_cmd, {
                'curwin': True,
                'term_kill': 'kill',
            })

        bufnr = self.vim.call('bufnr', '%')
        self._previewed_winid = self.vim.call('win_getid')
        self._vim.vars['denite#_previewing_bufnr'] = bufnr

        self.vim.call('win_gotoid', prev_id)
        self._previewed_target = target
