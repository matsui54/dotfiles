local on_attach = function(client)
  vim.wo.signcolumn = 'yes'
  local maps = {
    { 'n', '<c-]>',     '<cmd>lua vim.lsp.buf.definition()<CR>' },
    { 'n', 'K',         '<cmd>lua vim.lsp.buf.hover()<CR>' },
    { 'n', 'gD',        '<cmd>lua vim.lsp.buf.implementation()<CR>' },
    { 'n', '1gD',       '<cmd>lua vim.lsp.buf.type_definition()<CR>' },
    { 'n', 'gW',        '<cmd>lua vim.lsp.buf.workspace_symbol()<CR>' },
    { 'n', 'gd',        '<cmd>lua vim.lsp.buf.declaration()<CR>' },
    { 'n', 'ga',        '<cmd>lua vim.lsp.buf.code_action()<CR>' },
    { 'n', '<Leader>f', '<cmd>lua vim.lsp.buf.format({ async = true })<CR>' },
    { 'n', '<Leader>r', '<cmd>lua vim.lsp.buf.rename()<CR>' },
    { 'n', 'gl',        '<cmd>lua vim.lsp.buf.document_highlight()<CR>' },
    { 'n', 'gm',        '<cmd>lua vim.diagnostic.open_float()<CR>' },
    -- { 'n', 'g0', '<cmd>Denite lsp/document_symbol -auto-action=highlight<CR>' },
    { 'n', 'gr',        '<cmd>Denite lsp/references -auto-action=preview_bat<CR>' },
  }
  for _, map in ipairs(maps) do
    vim.api.nvim_buf_set_keymap(0, map[1], map[2], map[3], { noremap = true })
  end

  vim.lsp.handlers["textDocument/publishDiagnostics"] = vim.lsp.with(
    vim.lsp.diagnostic.on_publish_diagnostics, {
      virtual_text = false,
      severity_sort = true,
    }
  )
  -- require "lsp_signature".on_attach({
  --   floating_window = false,
  -- })  -- Note: add in lsp client on-attach

  local forceCompletionPattern = "\\.|:\\s*|->"
  if client.server_capabilities.completionProvider ~= nil then
    local triggers = client.server_capabilities.completionProvider.triggerCharacters
    local escaped = {}
    if triggers and #triggers > 0 then
      -- convert lsp triggerCharacters to js regexp
      for _, c in pairs(triggers) do
        local ch_list = { '[', '\\', '^', '$', '.', '|', '?', '*', '+', '(', ')' }
        if vim.tbl_contains(ch_list, c) then
          table.insert(escaped, '\\' .. c)
        else
          table.insert(escaped, c)
        end
      end
      forceCompletionPattern = table.concat(escaped, '|')
    end
  end
  -- add nvim-lsp source for ddc.vim
  -- override ddc setting of lsp buffer
  vim.fn['ddc#custom#patch_buffer']({
    sourceOptions = {
      ["nvim-lsp"] = {
        minAutoCompleteLength = 1,
        forceCompletionPattern = forceCompletionPattern,
      }
    },
  })
end

require("neodev").setup()

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
local nvim_lsp = require('lspconfig')

local node_root_dir = nvim_lsp.util.root_pattern("package.json", "node_modules")
local buf_name = vim.api.nvim_buf_get_name(0)
local current_buf = vim.api.nvim_get_current_buf()
local is_node_repo = node_root_dir(buf_name, current_buf) ~= nil

nvim_lsp.clangd.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.gopls.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.vimls.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.pyright.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.julials.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.bashls.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.texlab.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  root_dir = nvim_lsp.util.root_pattern('main.tex'),
  settings = {
    texlab = {
      rootDirectory = ".",
    }
  }
}
nvim_lsp.zls.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  cmd = { vim.fn.expand('$HOME/ghq/github.com/zigtools/zls/zig-out/bin/zls') },
}
nvim_lsp.denols.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  init_options = {
    lint = true,
    unstable = true,
  },
  autostart = not (is_node_repo),
}
nvim_lsp.lua_ls.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  settings = {
    Lua = {
      runtime = {
        version = 'LuaJIT',
        path = vim.split(package.path, ';'),
      },
      diagnostics = {
        globals = { 'vim' },
      },
      workspace = {
        library = {
          [vim.fn.expand('$VIMRUNTIME/lua')] = true,
          [vim.fn.expand('$VIMRUNTIME/lua/vim/lsp')] = true,
        },
      },
    },
  }
}
nvim_lsp.rust_analyzer.setup { on_attach = on_attach, capabilities = capabilities }
nvim_lsp.tsserver.setup {
  on_attach = on_attach,
  capabilities = capabilities,
  autostart = is_node_repo,
}
