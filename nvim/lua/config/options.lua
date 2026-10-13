-- General UI & Buffer settings
vim.opt.title = true
vim.opt.updatetime = 500
vim.opt.hidden = true
vim.opt.laststatus = 2
vim.opt.signcolumn = "yes"
vim.opt.termguicolors = true
vim.opt.mouse = "nv"
vim.opt.splitright = true
vim.opt.undofile = true

-- Indentation
vim.opt.expandtab = true
vim.opt.tabstop = 2
vim.opt.shiftwidth = 0
vim.opt.smartindent = true

-- Clipboard
vim.opt.clipboard = "unnamedplus"

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Matching
vim.opt.showmatch = true
vim.opt.matchpairs:append("<:>")

-- Completion
vim.opt.completeopt:remove("preview")

-- Localization & Language
vim.opt.helplang = { "en", "ja" }
pcall(vim.cmd, "language en_US.utf8")

-- File name characters
vim.opt.isfname:remove("=")

-- Tabline
vim.opt.showtabline = 2
vim.opt.tabline = "%!tabline#MyTabLine()"

-- Additional highlight settings for shirotelin
local function set_shirotelin_highlights()
  local bold_purple = { bold = true, fg = "#9425a8", ctermfg = 127 }
  vim.api.nvim_set_hl(0, "Special", bold_purple)
  vim.api.nvim_set_hl(0, "SpecialChar", bold_purple)
  vim.api.nvim_set_hl(0, "Tag", bold_purple)
  vim.api.nvim_set_hl(0, "Delimiter", bold_purple)

  vim.api.nvim_set_hl(0, "TabLineFill", { fg = "#999999" })
  vim.api.nvim_set_hl(0, "DiffAdd", { bg = "#C8FFC8", ctermbg = 194 })
  vim.api.nvim_set_hl(0, "DiffRemoved", { bg = "#FFC8C8", ctermbg = 224 })
  vim.api.nvim_set_hl(0, "LspSignatureActiveParameter", { underline = true })

  vim.api.nvim_set_hl(0, "@text.diff.add", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "@diff.plus", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "@text.diff.delete", { link = "DiffRemoved" })
  vim.api.nvim_set_hl(0, "@diff.minus", { link = "DiffRemoved" })
  vim.api.nvim_set_hl(0, "diffAdded", { link = "DiffAdd" })
  vim.api.nvim_set_hl(0, "diffRemoved", { link = "DiffRemoved" })

  vim.api.nvim_set_hl(0, "LspReferenceRead", { link = "ReferenceHighlight" })
  vim.api.nvim_set_hl(0, "LspReferenceText", { link = "ReferenceHighlight" })
  vim.api.nvim_set_hl(0, "LspReferenceWrite", { link = "ReferenceHighlight" })
  vim.api.nvim_set_hl(0, "FloatBorder", { link = "NormalFloat" })
end

local my_autocmd = vim.api.nvim_create_augroup("MyAutoCmd", { clear = true })
vim.api.nvim_create_autocmd("ColorScheme", {
  group = my_autocmd,
  callback = function(args)
    if args.match:find("shirotelin") then
      set_shirotelin_highlights()
    end
  end,
})

