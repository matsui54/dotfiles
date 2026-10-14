return {
  -- LSP Server Management & Configuration
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      "saghen/blink.cmp",
    },
    config = function()
      -- Diagnostics UI
      vim.diagnostic.config({
        virtual_text = false,
        severity_sort = true,
      })

      -- Keymaps & features on LspAttach
      vim.api.nvim_create_autocmd("LspAttach", {
        group = vim.api.nvim_create_augroup("my.lsp", { clear = true }),
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          local buf = args.buf
          vim.wo.signcolumn = "yes"

          local function map(mode, lhs, rhs, desc)
            vim.keymap.set(mode, lhs, rhs, { buffer = buf, desc = desc })
          end

          map("n", "<C-]>", vim.lsp.buf.definition, "LSP: Definition")
          map("n", "K", vim.lsp.buf.hover, "LSP: Hover")
          map("n", "gD", vim.lsp.buf.implementation, "LSP: Implementation")
          map("n", "1gD", vim.lsp.buf.type_definition, "LSP: Type Definition")
          map("n", "gW", vim.lsp.buf.workspace_symbol, "LSP: Workspace Symbol")
          map("n", "gd", vim.lsp.buf.declaration, "LSP: Declaration")
          map("n", "ga", vim.lsp.buf.code_action, "LSP: Code Action")
          map({ "n", "v" }, "<Leader>f", function() vim.lsp.buf.format({ async = true }) end, "LSP: Format")
          map("n", "<Leader>r", vim.lsp.buf.rename, "LSP: Rename")
          map("n", "gl", vim.lsp.buf.document_highlight, "LSP: Document Highlight")
          map("n", "gm", vim.diagnostic.open_float, "LSP: Diagnostic Float")
          map("n", "gr", vim.lsp.buf.references, "LSP: References")

          -- -- Inlay hints (Neovim 0.10+)
          -- if client and client:supports_method("textDocument/inlayHint") then
          --   vim.lsp.inlay_hint.enable(true, { bufnr = buf })
          -- end
        end,
      })

      vim.lsp.config("lua_ls", {
        settings = {
          Lua = {
            runtime = {
              version = "LuaJIT",
            },
            diagnostics = {
              globals = { "vim" },
            },
            workspace = {
              checkThirdParty = false,
            },
          },
        },
      })

      vim.lsp.config("slang-server", {
        cmd = { "slang-server" },
        root_markers = { ".git", ".slang" },
        filetypes = {
          "systemverilog",
          "verilog",
        },
      })

      -- Enable servers
      vim.lsp.enable({
        "clangd",
        "pyright",
        "slang-server",
      })
    end,
  },
}
