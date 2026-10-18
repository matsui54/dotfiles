return {
  -- lewis6991/gitsigns.nvim
  {
    'lewis6991/gitsigns.nvim',
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

  -- rhysd/git-messenger.vim
  {
    'rhysd/git-messenger.vim',
    cmd = 'GitMessenger',
    keys = {
      { '<Leader>gm', '<Plug>(git-messenger)', mode = 'n', desc = 'GitMessenger: Show blame popup' },
    },
    init = function()
      vim.g.git_messenger_no_default_mappings = true
      vim.g.git_messenger_always_into_popup = true
    end,
  },
  -- esmuellert/codediff.nvim
  {
    'esmuellert/codediff.nvim',
    cmd = 'CodeDiff',
    keys = {
      { 'gs',  '<cmd>CodeDiff<CR>',         desc = 'CodeDiff: Git status / review' },
      { 'gnl', '<cmd>CodeDiff history<CR>', mode = { 'n', 'v' },                   desc = 'CodeDiff: Git history / log' },
    },
    opts = {},
    init = function()
      -- gitcommit ファイルタイプ時に spell check を有効化
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'gitcommit',
        callback = function()
          vim.opt_local.spell = true
        end,
        desc = 'Enable spell check in gitcommit',
      })
      -- codediff-explorer バッファローカルのキーマップ (旧 gin-status 相当)
      vim.api.nvim_create_autocmd('FileType', {
        pattern = 'codediff-explorer',
        callback = function(ev)
          vim.keymap.set('n', '<Space>gc', function()
            vim.cmd('Commit')
          end, { buffer = ev.buf, desc = 'Git: commit via guise' })
          vim.keymap.set('n', '<Space>gp', function()
            vim.notify('Git push 開始...', vim.log.levels.INFO)
            vim.fn.jobstart({ 'git', 'push' }, {
              on_exit = function(_, code)
                if code == 0 then
                  vim.notify('Git push done', vim.log.levels.INFO)
                else
                  vim.notify('Git push fail (code: ' .. code .. ')', vim.log.levels.ERROR)
                end
              end,
            })
          end, { buffer = ev.buf, desc = 'Git: push' })
        end,
        desc = 'Custom keymaps for codediff-explorer',
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
