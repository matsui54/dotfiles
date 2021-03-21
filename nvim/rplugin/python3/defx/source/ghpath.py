from __future__ import annotations
import requests
import json
import typing
from pathlib import Path
import fnmatch
import re

URL_FORMAT = 'https://api.github.com/repos/{}/{}/git/trees/{}?recursive=1'


class Gh:
    def __init__(self, vim):
        self.vim = vim


class GhPathTree:
    def __init__(self, owner, repo, branch, vim):
        self.vim = vim
        self.owner = owner
        self.repo = repo
        self.branch = branch
        self.file_tree = {}

    def init_tree(self):
        # data = self._get_tree()
        data = self._retrieve_repo_data()
        self._make_tree(data)

    def get_parent(self, path: str):
        path_element = path.split('/')
        parent_path = '/'.join(path_element[:-1])
        return parent_path

    def is_dir(self, path: str) -> bool:
        tree = self.get_dir_tree(path)
        return tree['is_directory']

    def get_dir_tree(self, path: str):
        path_element = path.split('/')
        current_node = self.file_tree
        for ele in path_element:
            for child in current_node['children']:
                if child['name'] == ele:
                    current_node = child
                    break
        return current_node

    def get_child(self, path: str) -> str:
        tree = self.get_dir_tree(path)
        for f in tree['children']:
            yield f['path']

    def _retrieve_repo_data(self):
        url = URL_FORMAT.format(self.owner, self.repo, self.branch)
        token = self._get_token()
        headers = {'Authorization': token,
                   'Accept': 'application/vnd.github.v3+json'}
        res = requests.get(url, headers=headers).json()
        return res['tree']

    def _make_tree(self, data):
        self.file_tree = {
            'name': '/',
            'path': '/',
            'children': [],
            'is_directory': True,
            'size': 4096,
        }

        for file in data:
            file['path'] = '/' + file['path']

        for file in data:
            self._make_node(file)

    def _make_node(self, file):
        path_element = file['path'].split('/')
        parent_path = '/'.join(path_element[:-1])
        parent_tree = self.get_dir_tree(parent_path)
        if file['type'] == 'tree':
            parent_tree['children'].append({
                'name': path_element[-1],
                'path': file['path'],
                'children': [],
                'is_directory': True,
                'url': file['url'],
                'size': 4096,
            })
        else:
            parent_tree['children'].append({
                'name': path_element[-1],
                'path': file['path'],
                'is_directory': False,
                'url': file['url'],
                'size': file['size'],
            })

    def _get_tree(self):
        with open(str(Path(__file__).parent) + '/ghdata.json', 'r') as f:
            data = json.load(f)
        return data['tree']

    def _get_token(self):
        # token = self.vim.vars.get('gh_defx_token', '')
        token = ''
        if token:
            return token
        token_path = Path.home().joinpath('.config/gh/hosts.yml')
        if not token_path.is_file():
            token_path = Path.home().joinpath('.config/gh/config.yml')
        with open(str(token_path.absolute()), 'r') as f:
            for line in f.readlines():
                if re.search('oauth_token', line):
                    return re.findall(r'oauth_token: (.*)', line)[0]


class GhPath:
    def __init__(self, tree: GhPathTree, path: str):
        self.tree: GhPathTree = tree
        self.path: str = path

    def __str__(self) -> str:
        return self.path

    def __eq__(self, other: GhPath) -> bool:
        other_path = GhPath(self.tree, str(other))
        return self.path == other_path.path

    def iterdir(self) -> typing.Iterable(GhPath):
        for f in self.tree.get_child(self.path):
            yield GhPath(self.tree, f)

    def is_dir(self) -> bool:
        return self.tree.is_dir(self.path)

    def match(self, pattern) -> bool:
        """
        Return True if this path matches the given pattern.
        """
        return fnmatch.fnmatch(self.name, pattern)

    def is_symlink(self) -> bool:
        return False

    @property
    def parent(self) -> GhPath:
        return GhPath(self.tree, self.tree.get_parent(self.path))

    @property
    def name(self) -> str:
        parts = self.path.split('/')
        return parts[-1]

    @property
    def suffix(self):
        """
        The final component's last suffix, if any.

        This includes the leading period. For example: '.txt'
        """
        name = self.name
        i = name.rfind('.')
        if 0 < i < len(name) - 1:
            return name[i:]
        else:
            return ''


if __name__ == '__main__':
    owner = 'matsui54'
    repo = 'dotfiles'
    branch = 'master'
    tree = GhPathTree(owner, repo, branch)
    print(tree._get_token())
    # tree.init_tree()
    # ghpath = GhPath(tree, '/')
    # print(ghpath)
