from pynvim import Nvim
import typing
import site
from pathlib import Path

from defx.base.source import Base
from defx.context import Context
from defx.util import error

site.addsitedir(str(Path(__file__).parent.parent))
from source.ghpath import GhPath, GhPathTree


class Source(Base):
    def __init__(self, vim: Nvim) -> None:
        super().__init__(vim)

        self.name = 'gh'

        from kind.gh import Kind
        self.kind: Kind = Kind(self.vim)

        self.ghtree: GhPathTree = None

    def init_tree(self, args):
        # owner = 'matsui54'
        # repo = 'dotfiles'
        # branch = 'master'
        self.ghtree = GhPathTree(args[0], args[1], args[2], self.vim)
        self.ghtree.init_tree()

    def get_root_candidate(
            self, context: Context, path: Path
    ) -> typing.Dict[str, typing.Any]:
        # self.vim.call('defx#util#print_message', str(path))
        if not self.ghtree:
            self.init_tree(self._parse_arg(path))

        path = self._get_ghpath(path)
        return {
            'word': self.ghtree.repo + str(path),
            'is_directory': True,
            'action__path': path,
        }

    def gather_candidates(
            self, context: Context, path: GhPath
    ) -> typing.List[typing.Dict[str, typing.Any]]:
        if not self.ghtree:
            self.init_tree(self._parse_arg(path))

        path = self._get_ghpath(path)

        candidates = []
        for f in path.iterdir():
            candidates.append({
                'word': f.name,
                'is_directory': f.is_dir(),
                'action__path': f,
            })
        return candidates

    def _parse_arg(self, path: Path) -> typing.List[str]:
        args = str(path.name).split(':')
        if len(args) < 3:
            error(self.vim, "owner, repository and branch name is required")
        elif len(args) > 3:
            error(self.vim, "too many arguments")
        return args

    def _get_ghpath(self, path: Path) -> GhPath:
        is_root = (str(path) == self.vim.call('getcwd'))
        if is_root:
            path = GhPath(self.ghtree, '/')
        else:
            path = GhPath(self.ghtree, str(path))
        return path
