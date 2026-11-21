local actions = require('my.finder.actions')
local backend = require('my.finder.backend')
local ui = require('my.finder.ui')

local M = {}

---@param cwd string
---@param path string|nil
---@return string
local function to_rel_path(cwd, path)
  if not path or path == '' then
    return '[No Name]'
  end
  local norm_cwd = vim.fs.normalize(cwd)
  local norm_path = vim.fs.normalize(path)
  if norm_path:sub(1, #norm_cwd + 1) == norm_cwd .. '/' then
    return norm_path:sub(#norm_cwd + 2)
  end
  return vim.fn.fnamemodify(path, ':~')
end

---@param raw_text string|nil
---@param fallback_kind string|nil
---@return string, string
local function split_symbol_kind(raw_text, fallback_kind)
  local text = (raw_text or ''):gsub('[\r\n]+', ' ')
  local extracted, rest = text:match('^%[([^%]]+)%]%s*(.+)$')
  local kind = (fallback_kind and fallback_kind ~= '') and fallback_kind or extracted or 'Symbol'
  local name = rest or text
  return kind, name
end

---@param name string
---@param title string
---@param prompt string
---@param entries table[]
---@param match_texts string[]
---@return table
local function make_static_source(name, title, prompt, entries, match_texts)
  return {
    name = name,
    title = title,
    prompt = prompt,
    show_preview = true,
    allow_preview = true,

    prepare = function()
      return {
        entries = entries,
        match_texts = match_texts,
      }
    end,

    search = function(query, ctx)
      local res = backend.fuzzy_match_list(query, ctx.match_texts or {}, { limit = 200 })
      local items = {}
      for _, m in ipairs(res.items or {}) do
        local src = ctx.entries[m.idx]
        if src then
          items[#items + 1] = vim.tbl_extend('force', src, {
            match_indices = m.match_indices,
          })
        end
      end
      return {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_items or #ctx.entries,
        scanning = false,
      }
    end,
  }
end

---@param method string
---@param title string
---@param prompt string
---@param opts? table
local function open_location_picker(method, title, prompt, opts)
  opts = opts or {}
  local origin_win = vim.api.nvim_get_current_win()
  local origin_buf = vim.api.nvim_get_current_buf()

  local clients = vim.lsp.get_clients({ bufnr = origin_buf, method = method })
  if #clients == 0 then
    vim.notify('LSP: No active client supports ' .. method, vim.log.levels.INFO)
    return
  end

  local cwd = vim.fn.getcwd()
  local seen = {}
  local entries = {}
  local match_texts = {}
  local pending = #clients

  local function finish()
    if #entries == 0 then
      vim.notify('LSP: No ' .. title .. ' found', vim.log.levels.INFO)
      return
    end
    if #entries == 1 and opts.jump1 ~= false then
      actions.open_files({ entries[1] }, 'edit', { origin_win = origin_win })
      return
    end
    local source = make_static_source('lsp_' .. title:lower():gsub('%s+', '_'), title, prompt, entries, match_texts)
    ui.open(source, opts)
  end

  for _, client in ipairs(clients) do
    local encoding = client.offset_encoding or 'utf-16'
    local params = vim.lsp.util.make_position_params(origin_win, encoding)
    if method == 'textDocument/references' then
      params.context = { includeDeclaration = true }
    end

    local ok = client:request(method, params, function(err, result)
      pending = pending - 1
      if not err and result then
        local locs
        if result.uri or result.targetUri then
          locs = { result }
        elseif vim.islist(result) then
          locs = result
        else
          locs = {}
        end

        local qf_items = vim.lsp.util.locations_to_items(locs, encoding)
        for _, it in ipairs(qf_items) do
          local path = it.filename
          if path and path ~= '' then
            local lnum = it.lnum or 1
            local col_0 = math.max(0, (it.col or 1) - 1)
            local id = string.format('%s:%d:%d', vim.fs.normalize(path), lnum, col_0)
            if not seen[id] then
              seen[id] = true
              local rel_path = to_rel_path(cwd, path)
              local raw_text = (it.text or ''):gsub('[\r\n]+', ' ')
              local trimmed = raw_text:gsub('^%s+', '')
              local loc_str = string.format('%s:%d:%d: ', rel_path, lnum, col_0 + 1)
              local display = loc_str .. trimmed

              local ranges = nil
              if it.end_lnum == lnum and it.end_col and it.end_col > (it.col or 1) then
                ranges = { { col_0, it.end_col - 1 } }
              end

              entries[#entries + 1] = {
                id = id,
                path = path,
                rel_path = rel_path,
                lnum = lnum,
                col = col_0,
                text = raw_text,
                match_ranges = ranges,
                display = display,
                highlights = {
                  { 0, #rel_path, 'Identifier' },
                  { #rel_path, #loc_str, 'Comment' },
                },
                match_offset = 0,
              }
              match_texts[#match_texts + 1] = display
            end
          end
        end
      end

      if pending == 0 then
        finish()
      end
    end, origin_buf)

    if not ok then
      pending = pending - 1
      if pending == 0 then
        finish()
      end
    end
  end
end

---@param opts? table
function M.definitions(opts)
  open_location_picker('textDocument/definition', 'Definitions', 'def> ', opts)
end

---@param opts? table
function M.declarations(opts)
  open_location_picker('textDocument/declaration', 'Declarations', 'decl> ', opts)
end

---@param opts? table
function M.implementations(opts)
  open_location_picker('textDocument/implementation', 'Implementations', 'impl> ', opts)
end

---@param opts? table
function M.typedefs(opts)
  open_location_picker('textDocument/typeDefinition', 'Type Definitions', 'type> ', opts)
end

---@param opts? table
function M.references(opts)
  open_location_picker('textDocument/references', 'References', 'ref> ', opts)
end

---@param opts? table
function M.document_symbols(opts)
  opts = opts or {}
  local origin_buf = vim.api.nvim_get_current_buf()
  local origin_path = vim.api.nvim_buf_get_name(origin_buf)
  local method = 'textDocument/documentSymbol'

  local clients = vim.lsp.get_clients({ bufnr = origin_buf, method = method })
  if #clients == 0 then
    vim.notify('LSP: No active client supports ' .. method, vim.log.levels.INFO)
    return
  end

  local entries = {}
  local match_texts = {}
  local pending = #clients

  local function finish()
    if #entries == 0 then
      vim.notify('LSP: No document symbols found', vim.log.levels.INFO)
      return
    end
    local source = make_static_source('lsp_document_symbols', 'Document Symbols', 'sym> ', entries, match_texts)
    ui.open(source, opts)
  end

  for _, client in ipairs(clients) do
    local encoding = client.offset_encoding or 'utf-16'
    local params = { textDocument = vim.lsp.util.make_text_document_params(origin_buf) }
    local ok = client:request(method, params, function(err, result)
      pending = pending - 1
      if not err and result and vim.islist(result) and #result > 0 then
        local sym_items = vim.lsp.util.symbols_to_items(result, origin_buf, encoding)
        for idx, it in ipairs(sym_items) do
          local kind, sym_name = split_symbol_kind(it.text, it.kind)
          local lnum = it.lnum or 1
          local col_0 = math.max(0, (it.col or 1) - 1)
          local kind_col = string.format('%-13s ', '[' .. kind .. ']')
          local line_suffix = string.format(' :%d', lnum)
          local display = kind_col .. sym_name .. line_suffix

          local ranges = nil
          if it.end_lnum == lnum and it.end_col and it.end_col > (it.col or 1) then
            ranges = { { col_0, it.end_col - 1 } }
          end

          entries[#entries + 1] = {
            id = string.format('dsym:%d:%d:%s:%d', lnum, col_0, sym_name, idx),
            bufnr = origin_buf,
            path = (it.filename and it.filename ~= '') and it.filename or (origin_path ~= '' and origin_path or nil),
            lnum = lnum,
            col = col_0,
            match_ranges = ranges,
            display = display,
            highlights = {
              { 0, #('[' .. kind .. ']'), 'Type' },
              { #kind_col + #sym_name, #display, 'Comment' },
            },
            match_offset = #kind_col,
          }
          match_texts[#match_texts + 1] = sym_name
        end
      end

      if pending == 0 then
        finish()
      end
    end, origin_buf)

    if not ok then
      pending = pending - 1
      if pending == 0 then
        finish()
      end
    end
  end
end

---@param ctx table
local function cancel_pending_requests(ctx)
  for _, req in ipairs(ctx.pending_requests or {}) do
    if req.client and req.id then
      pcall(req.client.cancel_request, req.client, req.id)
    end
  end
  ctx.pending_requests = {}
end

---@param opts? table
function M.live_workspace_symbols(opts)
  opts = opts or {}
  local origin_buf = vim.api.nvim_get_current_buf()
  local method = 'workspace/symbol'

  local clients = vim.lsp.get_clients({ bufnr = origin_buf, method = method })
  if #clients == 0 then
    clients = vim.lsp.get_clients({ method = method })
  end
  if #clients == 0 then
    vim.notify('LSP: No active client supports ' .. method, vim.log.levels.INFO)
    return
  end

  local cwd = vim.fn.getcwd()

  local source = {
    name = 'lsp_workspace_symbols',
    title = 'Workspace Symbols',
    prompt = 'wsym> ',
    show_preview = true,
    allow_preview = true,
    debounce_ms = 60,
    empty_hint = '  Press `i` to search workspace symbols...',

    prepare = function()
      return {
        clients = clients,
        cwd = cwd,
        req_gen = 0,
        pending_requests = {},
        last_items = {},
        last_total = 0,
      }
    end,

    on_close = cancel_pending_requests,

    search = function(query, ctx, async_cb)
      cancel_pending_requests(ctx)
      ctx.req_gen = (ctx.req_gen or 0) + 1
      local my_gen = ctx.req_gen

      local trimmed = vim.trim(query or '')
      if trimmed == '' then
        ctx.last_items = {}
        ctx.last_total = 0
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      local active_clients = {}
      for _, c in ipairs(ctx.clients or {}) do
        if not c:is_stopped() then
          active_clients[#active_clients + 1] = c
        end
      end
      if #active_clients == 0 then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      local collected = {}
      local match_texts = {}
      local seen = {}
      local pending = #active_clients

      local function emit_results()
        local res = backend.fuzzy_match_list(trimmed, match_texts, { limit = 200 })
        local ranked = {}
        if (res.total_matched or 0) > 0 then
          for _, m in ipairs(res.items or {}) do
            local src = collected[m.idx]
            if src then
              ranked[#ranked + 1] = vim.tbl_extend('force', src, {
                match_indices = m.match_indices,
              })
            end
          end
        else
          local limit = math.min(200, #collected)
          for i = 1, limit do
            ranked[i] = collected[i]
          end
        end

        local total_matched = (res.total_matched or 0) > 0 and res.total_matched or #collected
        ctx.last_items = ranked
        ctx.last_total = #collected

        async_cb({
          items = ranked,
          total_matched = total_matched,
          total_items = #collected,
          scanning = false,
        })
      end

      for _, client in ipairs(active_clients) do
        local encoding = client.offset_encoding or 'utf-16'
        local ok, req_id = client:request(method, { query = trimmed }, function(err, result)
          if my_gen ~= ctx.req_gen then
            return
          end
          pending = pending - 1
          if not err and result and vim.islist(result) and #result > 0 then
            local sym_items = vim.lsp.util.symbols_to_items(result, nil, encoding)
            for _, it in ipairs(sym_items) do
              local path = it.filename
              if path and path ~= '' then
                local kind, sym_name = split_symbol_kind(it.text, it.kind)
                local lnum = it.lnum or 1
                local col_0 = math.max(0, (it.col or 1) - 1)
                local id = string.format('%s:%d:%d:%s', vim.fs.normalize(path), lnum, col_0, sym_name)
                if not seen[id] then
                  seen[id] = true
                  local rel_path = to_rel_path(ctx.cwd, path)
                  local kind_col = string.format('%-13s ', '[' .. kind .. ']')
                  local loc_suffix = string.format('  %s:%d', rel_path, lnum)
                  local display = kind_col .. sym_name .. loc_suffix

                  local ranges = nil
                  if it.end_lnum == lnum and it.end_col and it.end_col > (it.col or 1) then
                    ranges = { { col_0, it.end_col - 1 } }
                  end

                  collected[#collected + 1] = {
                    id = id,
                    path = path,
                    rel_path = rel_path,
                    lnum = lnum,
                    col = col_0,
                    match_ranges = ranges,
                    display = display,
                    highlights = {
                      { 0, #('[' .. kind .. ']'), 'Type' },
                      { #kind_col + #sym_name, #display, 'Comment' },
                    },
                    match_offset = #kind_col,
                  }
                  match_texts[#match_texts + 1] = sym_name
                end
              end
            end
          end

          if pending == 0 then
            ctx.pending_requests = {}
            emit_results()
          end
        end, ctx.origin_buf)

        if ok and req_id then
          table.insert(ctx.pending_requests, { client = client, id = req_id })
        else
          pending = pending - 1
          if pending == 0 then
            emit_results()
          end
        end
      end

      return {
        items = ctx.last_items or {},
        total_matched = #(ctx.last_items or {}),
        total_items = ctx.last_total or 0,
        scanning = true,
      }
    end,
  }

  ui.open(source, opts)
end

return M
