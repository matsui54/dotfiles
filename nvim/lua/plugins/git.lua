vim.api.nvim_create_autocmd('BufReadCmd', {
  group = vim.api.nvim_create_augroup('my_git_status_restore', { clear = true }),
  pattern = 'git-status://*',
  callback = function(ev)
    local root = ev.match:gsub('^git%-status://', '')
    require('my.git_status').open({ buf = ev.buf, root = root })
  end,
})

vim.api.nvim_create_autocmd('BufReadCmd', {
  group = vim.api.nvim_create_augroup('my_git_log_restore', { clear = true }),
  pattern = 'git-log://*',
  callback = function(ev)
    local root = ev.match:gsub('^git%-log://', '')
    require('my.git_log').open({ buf = ev.buf, root = root })
  end,
})

vim.api.nvim_create_user_command('GitStatus', function()
  require('my.git_status').open()
end, { desc = 'Open custom Git status buffer' })

vim.api.nvim_create_user_command('GitLog', function()
  require('my.git_log').open()
end, { desc = 'Open custom Git log buffer' })

vim.keymap.set('n', 'gs', function()
  require('my.git_status').open()
end, { desc = 'GitStatus: open' })

vim.keymap.set('n', 'gnl', function()
  require('my.git_log').open()
end, { desc = 'GitLog: open' })

vim.keymap.set('x', 'gnl', function()
  local l1 = vim.fn.line('v')
  local l2 = vim.fn.line('.')
  if l1 > l2 then
    l1, l2 = l2, l1
  end
  local file = vim.api.nvim_buf_get_name(0)
  local esc = vim.api.nvim_replace_termcodes('<Esc>', true, false, true)
  vim.api.nvim_feedkeys(esc, 'nx', false)
  require('my.git_log').open({ file = file, line_range = { l1, l2 } })
end, { desc = 'GitLog: line history' })

return {
  -- lewis6991/gitsigns.nvim
  {
    'lewis6991/gitsigns.nvim',
    cmd = 'Gitsigns',
    event = { 'BufReadPre', 'BufNewFile' },
    config = function()
      vim.api.nvim_set_hl(0, 'GitSignsAdd', { link = 'DiffAdd' })
      vim.api.nvim_set_hl(0, 'GitSignsChange', { link = 'DiffChange' })
      vim.api.nvim_set_hl(0, 'GitSignsDelete', { link = 'DiffDelete' })

      require('gitsigns').setup({
        signs = {
          change = { text = '!' },
        },
        on_attach = function(bufnr)
          local gs = package.loaded.gitsigns

          local function map(mode, l, r, opts)
            opts = opts or {}
            opts.buffer = bufnr
            vim.keymap.set(mode, l, r, opts)
          end

          -- Navigation
          map('n', ']c', function()
            if vim.wo.diff then return ']c' end
            vim.schedule(function() gs.next_hunk() end)
            return '<Ignore>'
          end, { expr = true, desc = 'Next hunk' })

          map('n', '[c', function()
            if vim.wo.diff then return '[c' end
            vim.schedule(function() gs.prev_hunk() end)
            return '<Ignore>'
          end, { expr = true, desc = 'Prev hunk' })

          -- Actions
          map({ 'n', 'v' }, '<leader>hs', ':Gitsigns stage_hunk<CR>', { desc = 'Stage hunk' })
          map({ 'n', 'v' }, '<leader>hr', ':Gitsigns reset_hunk<CR>', { desc = 'Reset hunk' })
          map('n', '<leader>hS', gs.stage_buffer, { desc = 'Stage buffer' })
          map('n', '<leader>hu', gs.undo_stage_hunk, { desc = 'Undo stage hunk' })
          map('n', '<leader>hR', gs.reset_buffer, { desc = 'Reset buffer' })
          map('n', '<leader>hp', gs.preview_hunk, { desc = 'Preview hunk' })
          map('n', '<leader>hb', function() gs.blame_line({ full = true }) end, { desc = 'Blame line full' })
          map('n', '<leader>tb', gs.toggle_current_line_blame, { desc = 'Toggle line blame' })
          map('n', '<leader>hd', gs.diffthis, { desc = 'Diff this' })
          map('n', '<leader>hD', function() gs.diffthis('~') end, { desc = 'Diff this ~' })
          map('n', '<leader>td', gs.toggle_deleted, { desc = 'Toggle deleted' })

          -- Text object
          map({ 'o', 'x' }, 'ih', ':<C-U>Gitsigns select_hunk<CR>', { desc = 'Select hunk' })
        end,
      })
    end,
  },

  -- lambdalisue/vim-guise
  {
    'lambdalisue/vim-guise',
    lazy = false,
    init = function()
      -- 新規インスタンスを起動せず、垂直分割で親 Neovim にバッファを開く
      vim.g.guise_edit_opener = 'vsplit'
    end,
    config = function()
      -- guise.server を確実に起動
      pcall(function()
        require('guise.server').start()
      end)

      -- Git は git config core.editor を EDITOR より優先するため、
      -- 最優先される GIT_EDITOR に guise の EDITOR を設定する
      if vim.env.EDITOR then
        vim.env.GIT_EDITOR = vim.env.EDITOR
      end

      -- 非同期ジョブで git commit を起動するコマンド (:Commit)
      vim.api.nvim_create_user_command('Commit', function(opts)
        local args = { 'git', 'commit' }
        if opts.args and opts.args ~= '' then
          vim.list_extend(args, vim.split(opts.args, '%s+'))
        end

        local editor = vim.env.GIT_EDITOR or vim.env.EDITOR
        local env = {}
        if editor then
          env.GIT_EDITOR = editor
        end

        local job_id = vim.fn.jobstart(args, {
          env = env,
          on_exit = function(_, code)
            if code == 0 then
              vim.notify('Git commit: Done', vim.log.levels.INFO)
              vim.schedule(function()
                local ok, gs = pcall(require, 'my.git_status')
                if ok and gs.is_open() then
                  gs.refresh()
                end
              end)
            end
          end,
        })
        if job_id <= 0 then
          vim.notify('Git commit: Fail', vim.log.levels.ERROR)
        end
      end, { nargs = '*', desc = 'Run non-blocking git commit via guise' })
    end,
  },
}
