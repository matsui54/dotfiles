import linecache
from pathlib import Path
import typing

from denite.base.source import Base
from denite.util import Nvim, UserContext, Candidates

SYMBOLS_HIGHLIGHT_SYNTAX = [
    {'name': 'Name', 'link': 'Constant',  're': r'\%(\] \zs\)\@<=\S*'},
    {'name': 'Type', 'link': 'Function',  're': r'\[\a\+\]'},
]


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)
        self.vim = vim
        self.name = "lsp/workspace_symbol"
        self.kind = "file"
        vim.exec_lua("_lsp_denite = require'lsp_denite'")

    def highlight(self) -> None:
        for syn in SYMBOLS_HIGHLIGHT_SYNTAX:
            self.vim.command(
                'syntax match {0}_{1} /{2}/ contained containedin={0}'.format(
                    self.syntax_name, syn['name'], syn['re']))
            self.vim.command(
                'highlight default link {}_{} {}'.format(
                    self.syntax_name, syn['name'], syn['link']))

    def on_init(self, context: UserContext) -> None:
        args = dict(enumerate(context['args']))
        context['__pattern'] = self._init_patterns(context, args)
        linecache.clearcache()

    def gather_candidates(self, context: UserContext) -> Candidates:
        candidates: Candidates = []
        items = self.vim.lua._lsp_denite.workspace_symbol(
            context['__pattern'])
        if not items:
            return []
        for item in items:
            path = Path(item["filename"])
            filename = path.name
            col = item["col"]
            lnum = item["lnum"]
            if self.vim.call('bufloaded', str(path)):
                bufnr = self.vim.call('bufnr', str(path))
                line = self.vim.call('getbufline', bufnr, lnum)[0]
            else:
                line = linecache.getline(str(path), lnum)

            word = "{}:{}:{} {}    {}".format(
                filename, str(lnum), str(col), item["text"], line
            )
            candidates.append(
                {
                    "word": word,
                    "action__path": str(path),
                    "action__line": lnum,
                    "action__col": col,
                }
            )
        return candidates

    def _init_patterns(self, context: UserContext,
                       args: typing.Dict[int, str]) -> typing.List[str]:
        pattern: str = ''
        arg: typing.Union[str, typing.List[str]] = args.get(0, [])
        if arg:
            if isinstance(arg, str):
                pattern = arg
            else:
                raise AttributeError(
                    '`args[0]` needs to be a `str`')
        elif context['input']:
            pattern = context['input']
        else:
            pattern = self.vim.call('denite#util#input', 'Query: ')
        return pattern
