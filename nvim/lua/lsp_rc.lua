vim.api.nvim_create_autocmd('LspAttach', {
  group = vim.api.nvim_create_augroup('my.lsp', {}),
  callback = function(args)
    local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
    vim.wo.signcolumn = 'yes'
    local maps = {
      { 'n', '<c-]>',     '<cmd>LspDefinition<CR>' },
      { 'n', 'K',         '<cmd>lua vim.lsp.buf.hover()<CR>' },
      { 'n', 'gD',        '<cmd>lua vim.lsp.buf.implementation()<CR>' },
      { 'n', '1gD',       '<cmd>lua vim.lsp.buf.type_definition()<CR>' },
      { 'n', 'gW',        '<cmd>lua vim.lsp.buf.workspace_symbol()<CR>' },
      { 'n', 'gd',        '<cmd>lua vim.lsp.buf.declaration()<CR>' },
      { 'n', 'ga',        '<cmd>lua vim.lsp.buf.code_action()<CR>' },
      { 'n', '<Leader>f', '<cmd>lua vim.lsp.buf.format()<CR>' },
      { 'v', '<Leader>f', '<cmd>lua vim.lsp.buf.format()<CR>' },
      { 'n', '<Leader>r', '<cmd>lua vim.lsp.buf.rename()<CR>' },
      { 'n', 'gl',        '<cmd>lua vim.lsp.buf.document_highlight()<CR>' },
      { 'n', 'gm',        '<cmd>lua vim.diagnostic.open_float()<CR>' },
      { 'n', 'gr',        '<cmd>LspReferences<CR>' },
    }
    for _, map in ipairs(maps) do
      vim.api.nvim_buf_set_keymap(0, map[1], map[2], map[3], { noremap = true })
    end

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
        ["lsp"] = {
          minAutoCompleteLength = 1,
          forceCompletionPattern = forceCompletionPattern,
        }
      },
    })
  end
})

require("lazydev").setup({
  library = {
    -- See the configuration section for more details
    -- Load luvit types when the `vim.uv` word is found
    { path = "${3rd}/luv/library", words = { "vim%.uv" } },
  },
})

vim.diagnostic.config({
  virtual_text = false,
  severity_sort = true,
})

local capabilities = require(
  "ddc_source_lsp"
).make_client_capabilities()

vim.lsp.config('*', {
  capabilities = capabilities,
})
vim.lsp.config('svlangserver', {
  settings = {
    systemverilog = {
      launchConfiguration = "verilator -sv -Wall --lint-only pkg_def.sv",
    }
  }
})
vim.lsp.config('texlab', {
  root_dir = vim.fs.root(0, 'main.tex'),
  settings = {
    texlab = {
      rootDirectory = ".",
    }
  }
})
vim.lsp.config('zls', {
  cmd = { vim.fn.expand('$HOME/ghq/github.com/zigtools/zls/zig-out/bin/zls') },
})
vim.lsp.config('denols', {
  init_options = {
    lint = true,
    unstable = true,
  },
})
vim.lsp.config('lua_ls', {
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
})
vim.lsp.config('efm', {
  init_options = { documentFormatting = true },
  settings = {
    rootMarkers = { ".git/" },
    languages = {
      markdown = {
        { formatCommand = "deno fmt - --ext md --line-width 200", formatStdin = true }
      },
      python = {
        { formatCommand = "black --quiet -", formatStdin = true }
      }
    }
  }
})
vim.lsp.config("slang-server", {
  cmd = { "slang-server" },
  root_markers = { ".git", ".slang" },
  filetypes = {
    "systemverilog",
    "verilog",
  },
})
vim.lsp.enable({ 'clangd', 'texlab', 'zls', 'lua_ls', 'rust_analyzer', 'gopls', 'vimls', 'pyright', 'julials', 'bashls',
  'hls' })

vim.api.nvim_create_autocmd("FileType", {
  group = vim.api.nvim_create_augroup("LspStartNodeOrDeno", { clear = true }),
  pattern = {
    "javascript", "javascriptreact", "javascript.jsx", "typescript", "typescriptreact", "typescript.tsx"
  },
  callback = function()
    if vim.fn.findfile("package.json", ".;") ~= "" then
      vim.lsp.start(vim.lsp.config.ts_ls)
      return
    end

    vim.lsp.start(vim.lsp.config.denols)
  end,
})
