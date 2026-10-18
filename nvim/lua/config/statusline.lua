-- Statusline configuration

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
vim.opt.laststatus = 2
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
