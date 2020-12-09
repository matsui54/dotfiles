local vim = vim
local util = require 'vim.lsp.util'

local M = {}

local symbol_handler = function(_, _, result, _, bufnr)
  if not result or vim.tbl_isempty(result) then return end
  vim.b.document_symbols = util.symbols_to_items(result, bufnr)
end

function M.document_symbol()
  local params = { textDocument = util.make_text_document_params() }
  vim.lsp.buf_request(0, 'textDocument/documentSymbol', params, symbol_handler)
  return vim.b.document_symbols
end

return M
