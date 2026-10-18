-- General UI & Buffer settings
vim.opt.title = true
vim.opt.updatetime = 500
vim.opt.hidden = true
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

-- Tabline & Statusline
vim.opt.showtabline = 2
vim.opt.tabline = "%!tabline#MyTabLine()"
vim.opt.laststatus = 2
-- Active バッファ用 statusline (Gitブランチ、LSP、診断等を含む完全版)
local function active_statusline()
  local parts = {}

  -- 左側: ファイル名 (%< で必要時に切り詰め)
  table.insert(parts, "%<%f")

  -- バッファ状態フラグ: ヘルプ (%h), プレビュー (%w), 変更 [%+], 読み込み専用 [RO], ターミナル終了コード
  table.insert(parts, "%( %h%w%m%r%{v:lua.require('vim._core.util').term_exitcode()}%)")

  -- 非同期 Git ブランチ (gitsigns キャッシュ)
  local branch = vim.b.gitsigns_head
  if branch and branch ~= "" then
    table.insert(parts, " [" .. branch .. "]")
  end

  -- 右寄せセパレータ
  table.insert(parts, "%=")

  -- 入力中キー (showcmdloc=statusline の場合)
  table.insert(parts, " %(%-10S %)")

  -- ビジースピナー
  if vim.o.busy and vim.o.busy > 0 then
    table.insert(parts, "◐ ")
  end

  -- LSP 進行状況
  if package.loaded["vim.ui"] then
    local progress = vim.ui.progress_status()
    if progress and progress ~= "" then
      table.insert(parts, progress .. " ")
    end
  end

  -- LSP 診断カウント (E:1 W:1 など)
  if package.loaded["vim.diagnostic"] and next(vim.diagnostic.count(0)) then
    local diag = vim.diagnostic.status()
    if diag and diag ~= "" then
      table.insert(parts, diag .. " ")
    end
  end

  -- ルーラー (%l: 行, %c%V: 列, %P: 位置%)
  if vim.o.ruler then
    table.insert(parts, vim.o.rulerformat ~= "" and vim.o.rulerformat or "%18(%l,%c%V%= %P%)%<")
  end

  return table.concat(parts)
end

-- Inactive バッファ用 statusline (GitブランチやLSPを省いたシンプル表示)
local function inactive_statusline()
  local parts = {}

  -- 左側: ファイル名 (%< で必要時に切り詰め)
  table.insert(parts, "%<%f")

  -- バッファ状態フラグ: ヘルプ (%h), プレビュー (%w), 変更 [%+], 読み込み専用 [RO], ターミナル終了コード
  table.insert(parts, "%( %h%w%m%r%{v:lua.require('vim._core.util').term_exitcode()}%)")

  -- 右寄せセパレータ
  table.insert(parts, "%=")

  -- ルーラー (%l: 行, %c%V: 列, %P: 位置%)
  if vim.o.ruler then
    table.insert(parts, vim.o.rulerformat ~= "" and vim.o.rulerformat or "%18(%l,%c%V%= %P%)%<")
  end

  return table.concat(parts)
end

-- Statusline 定義
_G.Statusline = {
  active = active_statusline,
  inactive = inactive_statusline,
}

-- デフォルトのステータスライン
vim.opt.statusline = "%!v:lua.Statusline.active()"

-- ウィンドウのフォーカス出入りに応じてローカル statusline を切り替え
local statusline_group = vim.api.nvim_create_augroup("StatuslineSwitch", { clear = true })

vim.api.nvim_create_autocmd({ "WinEnter", "BufEnter" }, {
  group = statusline_group,
  callback = function()
    vim.wo.statusline = "%!v:lua.Statusline.active()"
  end,
  desc = "Set active statusline",
})

vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
  group = statusline_group,
  callback = function()
    vim.wo.statusline = "%!v:lua.Statusline.inactive()"
  end,
  desc = "Set inactive statusline",
})

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
  vim.api.nvim_set_hl(0, "DiagnosticSignError", { fg = "#ff5555", bold = true })
  vim.api.nvim_set_hl(0, "DiagnosticSignWarn",  { fg = "#ff8c00", bold = true })
  vim.api.nvim_set_hl(0, "DiagnosticSignInfo",  { fg = "#f5cc00", bold = true })
  vim.api.nvim_set_hl(0, "DiagnosticSignHint",  { fg = "#9C83FF", bold = true })

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

