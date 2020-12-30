import simplenote
import re

from denite.base.source import Base
from denite.kind.openable import Kind
from denite.util import Nvim, UserContext, Candidates

SYMBOLS_HIGHLIGHT_SYNTAX = [
    # {'name': 'Type', 'link': 'Function',  're': r'\[\a\+\]'},
    # {'name': 'Name', 'link': 'Constant',  're': r'\w\+$'},
    # {'name': 'line', 'link': 'PreProc',   're': r'^ *\zs\d\+'},
    # {'name': 'col',  'link': 'Statement', 're': r'^ *\d\+ *\zs\d\+'},
]


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "simplenote"
        self.kind = Kind(vim)
        self.usr_name = self.vim.call('get', vim.eval('g:'), 'simplenote_user')
        self.password = self.vim.call('get',
                                      vim.eval('g:'), 'simplenote_password')
        self.sn = simplenote.Simplenote(self.usr_name, self.password)

    def highlight(self) -> None:
        for syn in SYMBOLS_HIGHLIGHT_SYNTAX:
            self.vim.command(
                'syntax match {0}_{1} /{2}/ contained containedin={0}'.format(
                    self.syntax_name, syn['name'], syn['re']))
            self.vim.command(
                'highlight default link {}_{} {}'.format(
                    self.syntax_name, syn['name'], syn['link']))

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        items = self.sn.get_note_list()[0]
        if not items:
            return []
        for item in items:
            if item['deleted']:
                continue
            content = item['content']
            m = re.match('[# ]*([^\n]*)\n', content)
            title = m.groups()[0]
            is_markdown = 'markdown' in item['systemtags']
            candidates.append(
                {
                    "word": title,
                    "__content": content,
                    "__is_md": is_markdown
                }
            )
        return candidates


class Kind(Kind):

    def __init__(self, vim):
        super().__init__(vim)
        self.default_action = "edit"
        self.name = "simplenote"

    def action_edit(self, context):
        target = context["targets"][0]
        self.vim.command('let g:hoge="{}"'.format(target['__content']))

    def action_preview(self, context):
        # 色付きのファイルだと遅い!
        target = context["targets"][0]
        self.vim.command(
            r"pedit +normal\ {}G {}".format(
                target["action__line"], target["action__path"]
            )
        )
