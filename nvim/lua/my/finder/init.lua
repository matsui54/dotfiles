local backend = require('my.finder.backend')
local ui = require('my.finder.ui')

local M = {}

local command_registered = false
local frecency_registered = false

local function register_command()
  if command_registered then
    return
  end
  command_registered = true
  vim.api.nvim_create_user_command('MyFinderBuild', function()
    backend.build({ sync = false })
  end, { desc = 'Build my.finder native Rust core' })
end

---@param buf integer
local function track_buf(buf)
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  if vim.bo[buf].buftype ~= '' then
    return
  end
  local path = vim.api.nvim_buf_get_name(buf)
  if not path or path == '' or path:match('^%a[%w+.-]*://') then
    return
  end
  local uv = vim.uv or vim.loop
  uv.fs_stat(path, function(err, st)
    if err or not st or st.type ~= 'file' then
      return
    end
    vim.schedule(function()
      backend.track_access(path)
    end)
  end)
end

local function register_frecency_autocmds()
  if frecency_registered then
    return
  end
  frecency_registered = true
  local group = vim.api.nvim_create_augroup('my_finder_frecency', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufEnter' }, {
    group = group,
    callback = function(args)
      track_buf(args.buf)
    end,
  })
  track_buf(vim.api.nvim_get_current_buf())
end

---@param opts? { state_dir?: string, base_path?: string, quiet?: boolean }
---@return boolean
function M.init(opts)
  register_command()
  local ok = backend.init(opts)
  if ok then
    register_frecency_autocmds()
  end
  return ok
end

---@param opts? { sync?: boolean }
function M.build(opts)
  register_command()
  return backend.build(opts)
end

---@param opts? table
function M.files(opts)
  register_command()
  local source = require('my.finder.sources.files').new()
  ui.open(source, opts)
end

---@param dir string
---@param opts? table
function M.files_in_dir(dir, opts)
  register_command()
  local o = vim.tbl_extend('force', opts or {}, { dir = dir })
  local source = require('my.finder.sources.files').new({ dir = dir, name = 'files_in_dir', title = 'Files (' .. dir .. ')' })
  ui.open(source, o)
end

---@param opts? table
function M.live_grep(opts)
  register_command()
  local source = require('my.finder.sources.grep').new()
  ui.open(source, opts)
end

---@param opts? table
function M.buffers(opts)
  register_command()
  local source = require('my.finder.sources.buffers').new()
  ui.open(source, opts)
end

---@param opts? table
function M.oldfiles(opts)
  register_command()
  local source = require('my.finder.sources.oldfiles').new()
  ui.open(source, opts)
end

---@param opts? table
function M.git_branches(opts)
  register_command()
  local source = require('my.finder.sources.git_branches').new()
  ui.open(source, opts)
end

---@param opts? table
function M.help_tags(opts)
  register_command()
  local source = require('my.finder.sources.help').new()
  ui.open(source, opts)
end

---@param opts? table
function M.manpages(opts)
  register_command()
  local source = require('my.finder.sources.man').new()
  ui.open(source, opts)
end

---@param opts? table
function M.command_history(opts)
  register_command()
  local source = require('my.finder.sources.cmdhist').new()
  ui.open(source, opts)
end

function M.resume()
  register_command()
  ui.resume()
end

local ui_select_registered = false

function M.register_ui_select()
  register_command()
  if ui_select_registered then
    return
  end
  ui_select_registered = true
  vim.ui.select = function(items, opts, on_choice)
    local source = require('my.finder.sources.ui_select').new(items, opts, on_choice)
    ui.open(source, {})
  end
end

---@param opts? table
function M.lsp_definitions(opts)
  register_command()
  require('my.finder.sources.lsp').definitions(opts)
end

---@param opts? table
function M.lsp_declarations(opts)
  register_command()
  require('my.finder.sources.lsp').declarations(opts)
end

---@param opts? table
function M.lsp_implementations(opts)
  register_command()
  require('my.finder.sources.lsp').implementations(opts)
end

---@param opts? table
function M.lsp_typedefs(opts)
  register_command()
  require('my.finder.sources.lsp').typedefs(opts)
end

---@param opts? table
function M.lsp_references(opts)
  register_command()
  require('my.finder.sources.lsp').references(opts)
end

---@param opts? table
function M.lsp_document_symbols(opts)
  register_command()
  require('my.finder.sources.lsp').document_symbols(opts)
end

---@param opts? table
function M.lsp_live_workspace_symbols(opts)
  register_command()
  require('my.finder.sources.lsp').live_workspace_symbols(opts)
end

function M.lsp_code_actions()
  M.register_ui_select()
  vim.lsp.buf.code_action()
end

return M
