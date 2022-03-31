local on_attach = function(client)
  vim.wo.signcolumn = 'yes'
  local maps = {
    {'n', '<c-]>',     '<cmd>lua vim.lsp.buf.definition()<CR>'},
    {'n', 'K',         '<cmd>lua vim.lsp.buf.hover()<CR>'},
    {'n', 'gD',        '<cmd>lua vim.lsp.buf.implementation()<CR>'},
    {'n', '1gD',       '<cmd>lua vim.lsp.buf.type_definition()<CR>'},
    {'n', 'gW',        '<cmd>lua vim.lsp.buf.workspace_symbol()<CR>'},
    {'n', 'gd',        '<cmd>lua vim.lsp.buf.declaration()<CR>'},
    {'n', 'ga',        '<cmd>lua vim.lsp.buf.code_action()<CR>'},
    {'n', '<Leader>f', '<cmd>lua vim.lsp.buf.formatting()<CR>'},
    {'n', '<Leader>r', '<cmd>lua vim.lsp.buf.rename()<CR>'},
    {'n', 'gl',        '<cmd>lua vim.lsp.buf.document_highlight()<CR>'},
    {'n', 'gm',        '<cmd>lua vim.diagnostic.open_float()<CR>'},
    {'n', 'g0',        '<cmd>Denite lsp/document_symbol -auto-action=highlight<CR>'},
    {'n', 'gr',        '<cmd>Denite lsp/references -auto-action=preview_bat<CR>'},
  }
  for _, map in ipairs(maps) do
    vim.api.nvim_buf_set_keymap(0, map[1], map[2], map[3], {noremap = true})
  end

  vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
      virtual_text = false,
    }
  )
  -- require "lsp_signature".on_attach({
  --   floating_window = false,
  -- })  -- Note: add in lsp client on-attach

  local triggers = client.server_capabilities.completionProvider.triggerCharacters
  local escaped = {}
  if triggers and #triggers > 0 then
    -- convert lsp triggerCharacters to js regexp
    for i, c in pairs(triggers) do
      local ch_list = {'[', '\\', '^', '$', '.', '|', '?', '*', '+', '(', ')'}
      if vim.tbl_contains(ch_list, c) then
        table.insert(escaped, '\\'..c)
      else table.insert(escaped, c)
      end
    end
    -- override ddc setting of lsp buffer
    vim.fn['ddc#custom#patch_buffer'] {
      sourceOptions = {
        ["nvim-lsp"] = {
          forceCompletionPattern = table.concat(escaped, '|'),
        }
      },
    }
  end

  if client.server_capabilities.documentHighlightProvider then
    vim.api.nvim_exec(
    [[
      augroup MyLspSettings
        autocmd!
        autocmd CursorHold  <buffer> lua vim.lsp.buf.document_highlight()
        autocmd CursorHoldI <buffer> lua vim.lsp.buf.document_highlight()
        autocmd CursorMoved <buffer> lua vim.lsp.buf.clear_references()
      augroup END
    ]],
    false)
  end
end

-- The nvim-cmp almost supports LSP's capabilities so You should advertise it to LSP servers..
local capabilities = vim.lsp.protocol.make_client_capabilities()
capabilities.textDocument.completion.completionItem.preselectSupport = false
capabilities.textDocument.completion.completionItem.insertReplaceSupport = false
capabilities.textDocument.completion.completionItem.labelDetailsSupport = false
capabilities.textDocument.completion.completionItem.snippetSupport = true
capabilities.textDocument.completion.completionItem.deprecatedSupport = false
capabilities.textDocument.completion.completionItem.commitCharactersSupport = false
-- capabilities.textDocument.completion.completionItem.tagSupport = { valueSet = { 1 } }
capabilities.textDocument.completion.completionItem.resolveSupport = {
  properties = {
    'documentation',
    'detail',
    -- 'additionalTextEdits',
  }
}

local lsp_installer = require("nvim-lsp-installer")
local nvim_lsp = require('lspconfig')

local node_root_dir = nvim_lsp.util.root_pattern("package.json", "node_modules")
local buf_name = vim.api.nvim_buf_get_name(0)
local current_buf = vim.api.nvim_get_current_buf()
local is_node_repo = node_root_dir(buf_name, current_buf) ~= nil

nvim_lsp.clangd.setup{on_attach = on_attach, capabilities = capabilities}
-- nvim_lsp.pylsp.setup{on_attach = on_attach, capabilities = capabilities}
nvim_lsp.rust_analyzer.setup{on_attach = on_attach, capabilities = capabilities}
-- nvim_lsp.texlab.setup{on_attach = on_attach, capabilities = capabilities}
nvim_lsp.gopls.setup{on_attach = on_attach, capabilities = capabilities}
nvim_lsp.denols.setup{
  on_attach = on_attach,
  capabilities = capabilities,
  init_options = {
    lint = true,
    unstable = true,
  },
  autostart = not(is_node_repo),
}

lsp_installer.on_server_ready(function(server)
  local opts = {}

  if server.name == 'sumneko_lua' then
    opts.settings = {
      Lua = {
        runtime = {
          version = 'LuaJIT',
          path = vim.split(package.path, ';'),
        },
        diagnostics = {
          globals = {'vim'},
        },
        workspace = {
          library = {
            [vim.fn.expand('$VIMRUNTIME/lua')] = true,
            [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true,
          },
        },
      },
    }
  elseif server.name == "tsserver" or server.name == "eslint" then
    opts.autostart = is_node_repo
  end

  opts.on_attach = on_attach
  opts.capabilities = capabilities
  server:setup(opts)
end)
