local dap = require('dap')
local dapui = require("dapui")

local get_python_path = function()
  local cwd = vim.fn.getcwd()
  if vim.fn.executable(cwd .. '/venv/bin/python') == 1 then
    return cwd .. '/venv/bin/python'
  elseif vim.fn.executable(cwd .. '/.venv/bin/python') == 1 then
    return cwd .. '/.venv/bin/python'
  elseif vim.fn.executable('python3') == 1 then
    return 'python3'
  elseif vim.fn.executable('python') == 1 then
    return 'python'
  else
    return '/usr/bin/python'
  end
end

dap.adapters.python = {
  type = 'executable';
  command = get_python_path();
  args = { '-m', 'debugpy.adapter' };
}

dap.adapters.cppdbg = {
  id = 'cppdbg',
  type = 'executable',
  command = 'OpenDebugAD7',
}

dap.configurations.python = {
  {
    -- The first three options are required by nvim-dap
    type = 'python'; -- the type here established the link to the adapter definition: `dap.adapters.python`
    request = 'launch';
    name = "Launch file";

    -- Options below are for debugpy, see https://github.com/microsoft/debugpy/wiki/Debug-configuration-settings for supported options

    program = "${file}"; -- This configuration will launch the current file if used.
    pythonPath = get_python_path;
  },
}

local c_cpp_config = {
  {
    name = "Launch file",
    type = "cppdbg",
    request = "launch",
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
    cwd = '${workspaceFolder}',
    stopOnEntry = true,
  },
  {
    name = 'Attach to gdbserver :1234',
    type = 'cppdbg',
    request = 'launch',
    MIMode = 'gdb',
    miDebuggerServerAddress = 'localhost:1234',
    miDebuggerPath = '/usr/bin/gdb',
    cwd = '${workspaceFolder}',
    program = function()
      return vim.fn.input('Path to executable: ', vim.fn.getcwd() .. '/', 'file')
    end,
  },
}

dap.configurations.cpp = c_cpp_config
dap.configurations.c = c_cpp_config

dap.listeners.after.event_initialized["dapui_config"] = function()
  dapui.open()
end
dap.listeners.before.event_terminated["dapui_config"] = function()
  dapui.close()
end
dap.listeners.before.event_exited["dapui_config"] = function()
  dapui.close()
end

vim.keymap.set('n', '<F5>', function() require 'dap'.continue() end)
vim.keymap.set('n', '<F9>', function() require 'dap'.step_into() end)
vim.keymap.set('n', '<F10>', function() require 'dap'.step_over() end)
vim.keymap.set('n', '<F12>', function() require 'dap'.step_out() end)
vim.keymap.set('n', '<Leader>b', function() require 'dap'.toggle_breakpoint() end)
