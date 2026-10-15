return {
  -- thinca/vim-quickrun
  {
    'thinca/vim-quickrun',
    dependencies = {
      'statiolake/vim-quickrun-runner-nvimterm',
    },
    cmd = 'QuickRun',
    keys = {
      { '<Leader>d', '<cmd>QuickRun<CR>', desc = 'QuickRun' },
    },
    config = function()
      vim.g.quickrun_config = {
        _ = {
          runner = 'nvimterm',
        },
        cpp = {
          cmdopt = '-std=c++2a -Wall',
          outputter = 'quickfix',
          ['outputter/message/log'] = 1,
        },
        ['cpp/compe'] = {
          type = 'cpp/g++',
          input = 'in.dat',
          runner = 'system',
        },
        vim = {
          command = ':source',
          exec = '%C %S',
          ['hook/eval/template'] = 'echo %s',
          runner = 'vimscript',
        },
        lua = {
          command = ':luafile',
          exec = '%C %S',
          runner = 'vimscript',
        },
        typescript = {
          type = 'typescript/deno',
        },
        gnuplot = {
          command = 'gnuplot',
          exec = '%C %S',
        },
        ['python/compe'] = {
          type = 'python',
          input = 'in.dat',
          runner = 'system',
        },
      }
    end,
  },
}
