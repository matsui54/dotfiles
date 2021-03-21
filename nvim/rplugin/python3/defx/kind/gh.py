from pathlib import Path
from pynvim import Nvim
import copy
import importlib
import mimetypes
import shlex
import shutil
import subprocess
import re
import time
import typing

from defx.action import ActionAttr
from defx.action import ActionTable
from defx.base.kind import Base
from defx.clipboard import ClipboardAction
from defx.context import Context
from defx.defx import Defx
from defx.util import cd, cwd_input, confirm, error, Candidate
from defx.util import readable, fnamemodify
from defx.view import View

_action_table: typing.Dict[str, ActionTable] = {}

ACTION_FUNC = typing.Callable[[View, Defx, Context], None]


def action(name: str, attr: ActionAttr = ActionAttr.NONE
           ) -> typing.Callable[[ACTION_FUNC], ACTION_FUNC]:
    def wrapper(func: ACTION_FUNC) -> ACTION_FUNC:
        _action_table[name] = ActionTable(func=func, attr=attr)

        def inner_wrapper(view: View, defx: Defx, context: Context) -> None:
            return func(view, defx, context)
        return inner_wrapper
    return wrapper


class Kind(Base):

    def __init__(self, vim: Nvim) -> None:
        self.vim = vim
        self.name = 'gh'

    def get_actions(self) -> typing.Dict[str, ActionTable]:
        actions = copy.copy(super().get_actions())
        actions.update(_action_table)
        return actions


def check_output(view: View, cwd: str, args: typing.List[str]) -> None:
    output = subprocess.check_output(args, cwd=cwd)
    if output:
        view.print_msg(output)


def check_overwrite(view: View, dest: Path, src: Path) -> Path:
    if not src.exists() or not dest.exists():
        return Path('')

    s_stat = src.stat()
    s_mtime = s_stat.st_mtime
    view.print_msg(f' src: {src} {s_stat.st_size} bytes')
    view.print_msg(f'      {time.strftime("%c", time.localtime(s_mtime))}')
    d_stat = dest.stat()
    d_mtime = d_stat.st_mtime
    view.print_msg(f'dest: {dest} {d_stat.st_size} bytes')
    view.print_msg(f'      {time.strftime("%c", time.localtime(d_mtime))}')

    choice: int = view._vim.call('defx#util#confirm',
                                 f'{dest} already exists.  Overwrite?',
                                 '&Force\n&No\n&Rename\n&Time\n&Underbar', 0)
    ret: Path = Path('')
    if choice == 1:
        ret = dest
    elif choice == 2:
        ret = Path('')
    elif choice == 3:
        ret = Path(view._vim.call(
            'defx#util#input',
            f'{src} -> ', str(dest),
            ('dir' if src.is_dir() else 'file')))
    elif choice == 4 and d_mtime < s_mtime:
        ret = src
    elif choice == 5:
        ret = Path(str(dest) + '_')
    return ret


def execute_job(view: View, args: typing.List[str]) -> None:
    view._vim.call('defx#util#close_async_job')

    if view._vim.call('has', 'nvim'):
        jobfunc = 'jobstart'
        jobopts = {}
    else:
        jobfunc = 'job_start'
        jobopts = {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'}

    view._vim.vars['defx#_async_job'] = view._vim.call(jobfunc, args, jobopts)


def switch(view: View) -> None:
    windows = [x for x in range(1, view._vim.call('winnr', '$') + 1)
               if view._vim.call('getwinvar', x, '&buftype') == '']

    result = view._vim.call('choosewin#start', windows,
                            {'auto_choose': True, 'hook_enable': False})
    if not result:
        # Open vertical
        view._vim.command('noautocmd rightbelow vnew')


@action(name='cd')
def _cd(view: View, defx: Defx, context: Context) -> None:
    """
    Change the current directory.
    """
    source_name = defx._source.name
    is_parent = context.args and context.args[0] == '..'
    prev_cwd = Path(defx._cwd)

    if is_parent:
        path = prev_cwd.parent
    else:
        if context.args:
            if len(context.args) > 1:
                source_name = context.args[0]
                path = Path(context.args[1])
            else:
                path = Path(context.args[0])
        else:
            path = Path.home()
        path = prev_cwd.joinpath(path)
        if not readable(path):
            error(view._vim, f'{path} is invalid.')
        path = path.resolve()
        if source_name == 'file' and not path.is_dir():
            error(view._vim, f'{path} is invalid.')
            return

    view.cd(defx, source_name, str(path), context.cursor)
    if is_parent:
        view.search_file(prev_cwd, defx._index)


@action(name='drop')
def _drop(view: View, defx: Defx, context: Context) -> None:
    """
    Open like :drop.
    """
    cwd = view._vim.call('getcwd', -1)
    command = context.args[0] if context.args else 'edit'

    for target in context.targets:
        path = target['action__path']

        if path.is_dir():
            view.cd(defx, defx._source.name, str(path), context.cursor)
            continue

        bufnr = view._vim.call('bufnr', f'^{path}$')
        winids = view._vim.call('win_findbuf', bufnr)

        if winids:
            view._vim.call('win_gotoid', winids[0])
        else:
            # Jump to the last accessed window
            view._vim.command('wincmd p')

            if view._vim.call('win_getid') == view._winid:
                view._vim.command('wincmd w')

            if not view._vim.call('haslocaldir'):
                try:
                    path = path.relative_to(cwd)
                except ValueError:
                    pass

            view._vim.call('defx#util#execute_path', command, str(path))

        view.restore_previous_buffer(view._prev_bufnr)
    view.close_preview()


@action(name='open')
def _open(view: View, defx: Defx, context: Context) -> None:
    """
    Open the file.
    """
    cwd = view._vim.call('getcwd', -1)
    command = context.args[0] if context.args else 'edit'
    choose = command == 'choose' and (
        view._vim.call('exists', 'g:loaded_choosewin')
        or view._vim.call('hasmapto', '<Plug>(choosewin)', 'n'))
    previewed_buffers = view._vim.vars['defx#_previewed_buffers']
    for target in context.targets:
        path = target['action__path']

        if target['is_directory']:
            view.cd(defx, defx._source.name, str(path), context.cursor)
            continue

        if not view._vim.call('haslocaldir'):
            try:
                path = path.relative_to(cwd)
            except ValueError:
                pass

        if choose:
            switch(view)

        view._vim.call('defx#util#execute_path',
                       'edit' if choose else command, str(path))

        bufnr = str(view._vim.call('bufnr', str(path)))
        if bufnr in previewed_buffers:
            previewed_buffers.pop(bufnr)
            view._vim.vars['defx#_previewed_buffers'] = previewed_buffers

        view.restore_previous_buffer(view._prev_bufnr)
    view.close_preview()


@action(name='open_directory')
def _open_directory(view: View, defx: Defx, context: Context) -> None:
    """
    Open the directory.
    """
    if context.args:
        path = Path(context.args[0])
    else:
        for target in context.targets:
            path = target['action__path']

    if path.is_dir():
        view.cd(defx, 'file', str(path), context.cursor)
