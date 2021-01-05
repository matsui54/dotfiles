local vim = vim
local util = require 'vim.lsp.util'

local M = {}

-- local symbol_handler = function(_, _, result, _, bufnr)
--   if not result or vim.tbl_isempty(result) then return end
--   vim.b.document_symbols = util.symbols_to_items(result, bufnr)
-- end
local function get_available_client(method)
  for id, client in pairs(vim.lsp.buf_get_clients()) do
    if client['resolved_capabilities'][method] == true then
      return id
    end
  end
  return 0
end

function M.references()
  local params = util.make_position_params()
  params.context = { includeDeclaration = true }

  local results_lsp = vim.lsp.buf_request_sync(0, "textDocument/references", params, 10000)
  local locations = {}
  for _, server_results in pairs(results_lsp) do
    if server_results.result then
      vim.list_extend(locations, vim.lsp.util.locations_to_items(server_results.result) or {})
    end
  end

  if vim.tbl_isempty(locations) then
    return nil
  end

  return locations
end

function M.document_symbol()
  local params = { textDocument = util.make_text_document_params() }
  local raw_result = vim.lsp.buf_request_sync(0, 'textDocument/documentSymbol', params, 1000)
  local client_id = get_available_client('document_symbol')
  if client_id == 0  or raw_result == nil then
    return nil
  end
  local result = util.symbols_to_items(raw_result[client_id].result, 0)
  return result
end

return M
