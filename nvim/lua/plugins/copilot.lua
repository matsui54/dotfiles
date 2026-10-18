return {
  {
    'github/copilot.vim',
    cmd = 'Copilot',
    event = 'InsertEnter',
    init = function()
      -- デフォルトの <Tab> キーによる候補確定を無効化
      vim.g.copilot_no_tab_map = true
    end,
    config = function()
      -- <C-v> で Copilot の提案を確定
      vim.keymap.set('i', '<C-v>', 'copilot#Accept("\\<CR>")', {
        expr = true,
        replace_keycodes = false,
        silent = true,
        desc = 'Copilot: Accept suggestion',
      })
    end,
  },
}
