local backend = require('my.finder.backend')
local git_util = require('my.finder.git_util')

local M = {}

local MAX_DIFF_PREVIEW_LINES = 1500

---@param code string
---@return string
local function hl_for_code(code)
  local c = code:sub(1, 1)
  if c == 'A' then
    return 'Added'
  elseif c == 'D' then
    return 'Removed'
  elseif c == 'M' or c == 'R' or c == 'C' then
    return 'Changed'
  elseif c == '?' then
    return 'Comment'
  elseif c == 'U' then
    return 'DiagnosticError'
  end
  return 'Normal'
end

---@param raw string
---@param root string
---@return table[], string[]
local function parse_status(raw, root)
  local staged = {}
  local unstaged = {}
  local items = vim.split(raw, '\0', { plain = true, trimempty = true })
  local i = 1

  while i <= #items do
    local item = items[i]
    if #item >= 4 then
      local x = item:sub(1, 1)
      local y = item:sub(2, 2)
      local path = item:sub(4)
      local orig_path = nil

      if x == 'R' or x == 'C' or y == 'R' or y == 'C' then
        i = i + 1
        orig_path = items[i]
      end

      if x == '?' and y == '?' then
        unstaged[#unstaged + 1] = {
          section = 'unstaged',
          code = '??',
          rel_path = path,
          orig_path = nil,
          key = 'unstaged:' .. path,
        }
      else
        if x ~= ' ' then
          staged[#staged + 1] = {
            section = 'staged',
            code = x,
            rel_path = path,
            orig_path = orig_path,
            key = 'staged:' .. path,
          }
        end
        if y ~= ' ' then
          unstaged[#unstaged + 1] = {
            section = 'unstaged',
            code = y,
            rel_path = path,
            orig_path = orig_path,
            key = 'unstaged:' .. path,
          }
        end
      end
    end
    i = i + 1
  end

  local raw_entries = vim.list_extend(staged, unstaged)
  local entries = {}
  local status_items = {}

  for _, e in ipairs(raw_entries) do
    local badge = (e.section == 'staged') and ' S ' or ' U '
    local code_str = string.format('%-2s', e.code)
    local display_path = e.orig_path and (e.orig_path .. ' -> ' .. e.rel_path) or e.rel_path
    local display = string.format('%s %s %s', badge, code_str, display_path)

    local badge_hl = (e.section == 'staged') and 'MyFinderGitStagedBadge' or 'MyFinderGitUnstagedBadge'

    local hls = {
      { 0, 3, badge_hl },
      { 4, 6, hl_for_code(e.code) },
    }

    entries[#entries + 1] = {
      id = e.key,
      key = e.key,
      section = e.section,
      code = e.code,
      rel_path = e.rel_path,
      orig_path = e.orig_path,
      path = root .. '/' .. e.rel_path,
      git_root = root,
      display = display,
      highlights = hls,
      match_offset = 7,
    }
    status_items[#status_items + 1] = {
      section = e.section,
      code = e.code,
      rel_path = e.rel_path,
      match_text = display_path,
    }
  end

  return entries, status_items
end

---@param ctx table
---@param on_done fun()
local function fetch_status(ctx, on_done)
  ctx.fetch_gen = (ctx.fetch_gen or 0) + 1
  local gen = ctx.fetch_gen
  local pending = 2

  local function finish_one()
    pending = pending - 1
    if pending == 0 then
      ctx.loading = false
      on_done()
    end
  end

  git_util.run_git(ctx.git_root, { 'rev-parse', '--abbrev-ref', 'HEAD' }, function(res)
    if gen ~= ctx.fetch_gen then
      return
    end
    local branch = '(HEAD)'
    if res.code == 0 and res.stdout then
      local trimmed = vim.trim(res.stdout)
      if trimmed ~= '' then
        branch = trimmed
      end
    end
    ctx.branch = branch
    ctx.prompt = string.format('status [%s]> ', branch)
    finish_one()
  end)

  git_util.run_git(ctx.git_root, { 'status', '--porcelain=v1', '-z', '-uall' }, function(res)
    if gen ~= ctx.fetch_gen then
      return
    end
    if res.code == 0 and res.stdout then
      local entries, status_items = parse_status(res.stdout, ctx.git_root)
      if #entries > 0 then
        local ranked = backend.search_git_status(ctx.git_root, '', status_items, {
          limit = 0,
          current_file = ctx.current_file,
        })
        if ranked and ranked.items and #ranked.items == #entries then
          local sorted_entries = {}
          local sorted_status_items = {}
          for _, m in ipairs(ranked.items) do
            sorted_entries[#sorted_entries + 1] = entries[m.idx]
            sorted_status_items[#sorted_status_items + 1] = status_items[m.idx]
          end
          entries = sorted_entries
          status_items = sorted_status_items
        end
      end
      ctx.entries, ctx.status_items = entries, status_items
    else
      ctx.entries, ctx.status_items = {}, {}
      local msg = git_util.trim_output(res)
      if msg ~= '' then
        vim.notify('git status failed: ' .. msg, vim.log.levels.ERROR)
      end
    end
    finish_one()
  end, { text = false })
end

---@param ctx table
---@param refresh_opts? boolean|table
local function reload_status(ctx, refresh_opts)
  if not ctx.git_root then
    return
  end
  fetch_status(ctx, function()
    ctx.refresh(refresh_opts ~= nil and refresh_opts or true)
  end)
end

---@param targets table[]
---@return string[], string[]
local function collect_paths_and_ids(targets)
  local seen = {}
  local paths = {}
  local ids = {}
  for _, it in ipairs(targets) do
    if it.id then
      ids[#ids + 1] = it.id
    end
    if it.orig_path and it.orig_path ~= '' and not seen[it.orig_path] then
      seen[it.orig_path] = true
      paths[#paths + 1] = it.orig_path
    end
    if it.rel_path and it.rel_path ~= '' and not seen[it.rel_path] then
      seen[it.rel_path] = true
      paths[#paths + 1] = it.rel_path
    end
  end
  return paths, ids
end

---@param targets table[]
---@param ctx table
---@return string
local function stage_targets(targets, ctx)
  local root = ctx.git_root
  if not root then
    return 'keep_open'
  end
  local paths, ids = collect_paths_and_ids(targets)
  if #paths == 0 then
    return 'keep_open'
  end

  local args = { 'add', '--' }
  vim.list_extend(args, paths)
  git_util.run_git(root, args, function(res)
    ctx.clear_marks(ids)
    if res.code ~= 0 then
      local msg = git_util.trim_output(res)
      vim.notify('git add failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
    end
    reload_status(ctx)
  end)

  return 'keep_open'
end

---@param targets table[]
---@param ctx table
---@return string
local function unstage_targets(targets, ctx)
  local root = ctx.git_root
  if not root then
    return 'keep_open'
  end
  local paths, ids = collect_paths_and_ids(targets)
  if #paths == 0 then
    return 'keep_open'
  end

  git_util.run_git(root, { 'rev-parse', '--verify', '--quiet', 'HEAD' }, function(head_res)
    local args = (head_res.code == 0) and { 'restore', '--staged', '--' } or { 'rm', '--cached', '-q', '--' }
    vim.list_extend(args, paths)
    git_util.run_git(root, args, function(res)
      ctx.clear_marks(ids)
      if res.code ~= 0 then
        local msg = git_util.trim_output(res)
        vim.notify('git unstage failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
      end
      reload_status(ctx)
    end)
  end)

  return 'keep_open'
end

---@param targets table[]
---@param ctx table
---@return string
local function discard_targets(targets, ctx)
  local root = ctx.git_root
  if not root then
    return 'keep_open'
  end

  local restore_seen = {}
  local clean_seen = {}
  local restore_paths = {}
  local clean_paths = {}
  local target_ids = {}
  local skipped_staged = {}

  for _, it in ipairs(targets) do
    if it.section == 'staged' then
      skipped_staged[#skipped_staged + 1] = it.rel_path
    elseif it.rel_path and it.rel_path ~= '' then
      target_ids[#target_ids + 1] = it.id
      if it.code == '??' then
        if not clean_seen[it.rel_path] then
          clean_seen[it.rel_path] = true
          clean_paths[#clean_paths + 1] = it.rel_path
        end
      else
        if not restore_seen[it.rel_path] then
          restore_seen[it.rel_path] = true
          restore_paths[#restore_paths + 1] = it.rel_path
        end
      end
    end
  end

  if #restore_paths == 0 and #clean_paths == 0 then
    if #skipped_staged > 0 then
      vim.notify('Skipped staged file(s); unstage first: ' .. table.concat(skipped_staged, ', '), vim.log.levels.WARN)
    else
      vim.notify('Select unstaged item(s) to discard', vim.log.levels.WARN)
    end
    return 'keep_open'
  end

  local cmds = {}
  if #restore_paths > 0 then
    local args = { 'restore', '--worktree', '--' }
    vim.list_extend(args, restore_paths)
    cmds[#cmds + 1] = args
  end
  if #clean_paths > 0 then
    local args = { 'clean', '-f', '--' }
    vim.list_extend(args, clean_paths)
    cmds[#cmds + 1] = args
  end

  local extra_note = #skipped_staged > 0 and ('Skipped staged: ' .. table.concat(skipped_staged, ', ')) or nil
  if not git_util.confirm_git_cmds(ctx, cmds, extra_note) then
    return 'keep_open'
  end

  local errors = {}
  local idx = 1
  local function step()
    if idx > #cmds then
      pcall(vim.cmd, 'checktime')
      ctx.clear_marks(target_ids)
      if #errors == 0 then
        vim.notify('Discarded unstaged changes', vim.log.levels.INFO)
      else
        vim.notify('Discard failed:\n' .. table.concat(errors, '\n'), vim.log.levels.ERROR)
      end
      reload_status(ctx)
      return
    end
    local args = cmds[idx]
    idx = idx + 1
    git_util.run_git(root, args, function(res)
      if res.code ~= 0 then
        local msg = git_util.trim_output(res)
        errors[#errors + 1] = git_util.format_git_cmd(args) .. (msg ~= '' and ': ' .. msg or '')
      end
      step()
    end)
  end
  step()

  return 'keep_open'
end

---@param root string
---@param extra_args? string[]
local function run_commit_and_reopen(root, extra_args)
  pcall(function()
    require('guise.server').start()
  end)

  local cmd = { 'git', '-C', root, 'commit' }
  if extra_args and #extra_args > 0 then
    vim.list_extend(cmd, extra_args)
  end

  local editor = vim.env.GIT_EDITOR or vim.env.EDITOR
  local env = editor and { GIT_EDITOR = editor } or nil
  local stderr_lines = {}

  local function reopen_status()
    vim.schedule(function()
      if not require('my.finder.ui').is_open() then
        require('my.finder').git_status({ git_root = root })
      end
    end)
  end

  local job_id = vim.fn.jobstart(cmd, {
    env = env,
    stderr_buffered = true,
    on_stderr = function(_, data)
      if type(data) == 'table' then
        for _, line in ipairs(data) do
          if line ~= '' then
            stderr_lines[#stderr_lines + 1] = line
          end
        end
      end
    end,
    on_exit = function(_, code)
      vim.schedule(function()
        if code == 0 then
          vim.notify('Git commit: Done', vim.log.levels.INFO)
          pcall(vim.cmd, 'checktime')
        else
          local msg = vim.trim(table.concat(stderr_lines, '\n'))
          vim.notify(
            msg ~= '' and ('Git commit aborted/failed: ' .. msg) or ('Git commit exited with code ' .. tostring(code)),
            vim.log.levels.WARN
          )
        end
        reopen_status()
      end)
    end,
  })

  if job_id <= 0 then
    vim.notify('Git commit: Fail', vim.log.levels.ERROR)
    reopen_status()
  end
end

---@param label string
---@param count integer
---@param header_hl string
---@return table
local function build_section_header(label, count, header_hl)
  local title = string.format(' %s (%d) ', label, count)
  local rule_len = math.max(4, 42 - #title)
  return {
    { '──', 'MyFinderSectionRule' },
    { title, header_hl },
    { string.rep('─', rule_len), 'MyFinderSectionRule' },
  }
end

function M.new()
  return {
    name = 'git_status',
    title = 'Git Status',
    prompt = 'status> ',
    scanning_hint = '  Loading...',
    empty_hint = '  (working tree clean)',
    show_preview = true,
    allow_preview = true,

    prepare = function(ctx, opts)
      local root = (opts and opts.git_root) or git_util.find_git_root(ctx.origin_path)
      local current_file = nil
      if root and ctx.origin_path and ctx.origin_path ~= '' then
        local norm_origin = vim.fs.normalize(ctx.origin_path)
        local norm_root = vim.fs.normalize(root)
        if norm_origin:sub(1, #norm_root + 1) == norm_root .. '/' then
          current_file = norm_origin:sub(#norm_root + 2)
        end
      end
      return {
        git_root = root,
        current_file = current_file,
        branch = nil,
        entries = nil,
        status_items = nil,
        loading = root ~= nil,
        fetch_gen = 0,
      }
    end,

    search = function(query, ctx, async_cb)
      if not ctx.git_root then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      local function build_response()
        local res = backend.search_git_status(ctx.git_root, query, ctx.status_items or {}, {
          limit = 500,
          current_file = ctx.current_file,
        })
        local matched = res.items or {}
        local staged_count = 0
        local unstaged_count = 0
        for _, m in ipairs(matched) do
          local src = ctx.entries[m.idx]
          if src then
            if src.section == 'staged' then
              staged_count = staged_count + 1
            else
              unstaged_count = unstaged_count + 1
            end
          end
        end

        local items = {}
        local seen_staged = false
        local seen_unstaged = false
        for _, m in ipairs(matched) do
          local src = ctx.entries[m.idx]
          if src then
            local virt_lines_above = nil
            if src.section == 'staged' and not seen_staged then
              seen_staged = true
              virt_lines_above = {
                build_section_header('Staged', staged_count, 'MyFinderGitStagedHeader'),
              }
            elseif src.section ~= 'staged' and not seen_unstaged then
              seen_unstaged = true
              virt_lines_above = {
                build_section_header('Unstaged', unstaged_count, 'MyFinderGitUnstagedHeader'),
              }
            end

            items[#items + 1] = vim.tbl_extend('force', src, {
              match_indices = m.match_indices,
              virt_lines_above = virt_lines_above,
            })
          end
        end
        return {
          items = items,
          total_matched = res.total_matched or #items,
          total_items = res.total_items or #ctx.entries,
          scanning = false,
        }
      end

      if ctx.entries then
        return build_response()
      end

      fetch_status(ctx, function()
        async_cb(build_response())
      end)

      return {
        items = {},
        total_matched = 0,
        total_items = 0,
        scanning = true,
      }
    end,

    preview = function(item, pctx, cb)
      if not item.git_root or not item.rel_path then
        cb({ '(no file)' }, { skip_ts = true })
        return
      end
      if item.code == '??' then
        pctx.preview_file(item.path)
        return
      end

      local args = { 'diff' }
      if item.section == 'staged' then
        args[#args + 1] = '--cached'
      end
      args[#args + 1] = '--no-color'
      args[#args + 1] = '--'
      if item.orig_path and item.orig_path ~= '' then
        args[#args + 1] = item.orig_path
      end
      args[#args + 1] = item.rel_path

      git_util.run_git(item.git_root, args, function(res)
        if pctx.is_stale() then
          return
        end
        if res.code ~= 0 then
          local msg = git_util.trim_output(res)
          cb({ 'git diff failed' .. (msg ~= '' and ': ' .. msg or '') }, { skip_ts = true })
          return
        end
        local lines = vim.split(res.stdout or '', '\n', { plain = true })
        if #lines > 1 and lines[#lines] == '' then
          table.remove(lines, #lines)
        end
        if #lines == 0 or (#lines == 1 and lines[1] == '') then
          cb({ '(no diff)' }, { skip_ts = true })
          return
        end
        if #lines > MAX_DIFF_PREVIEW_LINES then
          local truncated = {}
          for i = 1, MAX_DIFF_PREVIEW_LINES do
            truncated[i] = lines[i]
          end
          truncated[#truncated + 1] = string.format('... [diff truncated, total %d lines] ...', #lines)
          lines = truncated
        end
        local hls = git_util.highlight_diff_lines(lines)
        cb(lines, { skip_ts = true, highlights = hls })
      end, { text = false })
    end,

    keymaps = {
      ['<CR>'] = {
        action = 'diff',
        desc = 'Finder git_status: open diffthis tab',
      },
      ['<<'] = {
        mode = 'n',
        action = 'stage',
        desc = 'Finder git_status: stage',
      },
      ['<'] = {
        mode = 'x',
        action = 'stage',
        desc = 'Finder git_status: stage (visual)',
      },
      ['>>'] = {
        mode = 'n',
        action = 'unstage',
        desc = 'Finder git_status: unstage',
      },
      ['>'] = {
        mode = 'x',
        action = 'unstage',
        desc = 'Finder git_status: unstage (visual)',
      },
      r = {
        action = 'refresh',
        desc = 'Finder git_status: refresh',
      },
      ['<Space>gc'] = {
        action = 'commit',
        desc = 'Finder git_status: commit via guise',
      },
      ['<Space>gp'] = {
        action = 'push',
        desc = 'Finder git_status: git push',
      },
    },

    actions = {
      diff = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root then
          return 'keep_open'
        end
        local entries = ctx.entries or {}
        ctx.close()
        vim.schedule(function()
          git_util.open_status_diff_tab(it.git_root, it, entries, false)
        end)
      end,

      stage = function(targets, ctx)
        return stage_targets(targets, ctx)
      end,

      unstage = function(targets, ctx)
        return unstage_targets(targets, ctx)
      end,

      stage_all = {
        allow_empty = true,
        desc = 'Stage all changes (git add -A)',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          if not git_util.confirm_git_cmds(ctx, { { 'add', '-A' } }) then
            return 'keep_open'
          end
          git_util.run_git(ctx.git_root, { 'add', '-A' }, function(res)
            ctx.clear_marks(nil)
            if res.code ~= 0 then
              local msg = git_util.trim_output(res)
              vim.notify('git add -A failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
            end
            reload_status(ctx)
          end)
          return 'keep_open'
        end,
      },

      unstage_all = {
        allow_empty = true,
        desc = 'Unstage all changes',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          git_util.run_git(ctx.git_root, { 'rev-parse', '--verify', '--quiet', 'HEAD' }, function(head_res)
            local args = (head_res.code == 0) and { 'restore', '--staged', '.' } or { 'rm', '--cached', '-r', '-q', '.' }
            git_util.run_git(ctx.git_root, args, function(res)
              ctx.clear_marks(nil)
              if res.code ~= 0 then
                local msg = git_util.trim_output(res)
                vim.notify('git unstage all failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
              end
              reload_status(ctx)
            end)
          end)
          return 'keep_open'
        end,
      },

      discard = function(targets, ctx)
        return discard_targets(targets, ctx)
      end,

      commit = {
        allow_empty = true,
        desc = 'Commit via guise and reopen git_status',
        fn = function(_, ctx)
          local root = ctx.git_root
          if not root then
            vim.notify('Not inside a git repository', vim.log.levels.WARN)
            return 'keep_open'
          end
          ctx.close()
          vim.schedule(function()
            run_commit_and_reopen(root)
          end)
        end,
      },

      commit_amend = {
        allow_empty = true,
        desc = 'Commit --amend via guise and reopen git_status',
        fn = function(_, ctx)
          local root = ctx.git_root
          if not root then
            vim.notify('Not inside a git repository', vim.log.levels.WARN)
            return 'keep_open'
          end
          ctx.close()
          vim.schedule(function()
            run_commit_and_reopen(root, { '--amend' })
          end)
        end,
      },

      push = {
        allow_empty = true,
        desc = 'Run git push',
        fn = function(_, ctx)
          if not ctx.git_root then
            vim.notify('Not inside a git repository', vim.log.levels.WARN)
            return 'keep_open'
          end
          vim.notify('Git push 開始...', vim.log.levels.INFO)
          git_util.run_git(ctx.git_root, { 'push' }, function(res)
            if res.code == 0 then
              vim.notify('Git push done', vim.log.levels.INFO)
            else
              local msg = git_util.trim_output(res)
              vim.notify('Git push fail (code: ' .. res.code .. ')' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
            end
          end)
          return 'keep_open'
        end,
      },

      stash = {
        allow_empty = true,
        desc = 'Stash working tree changes',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          if not git_util.confirm_git_cmds(ctx, { { 'stash', 'push' } }) then
            return 'keep_open'
          end
          git_util.run_git(ctx.git_root, { 'stash', 'push' }, function(res)
            pcall(vim.cmd, 'checktime')
            ctx.clear_marks(nil)
            if res.code == 0 then
              local msg = git_util.trim_output(res)
              vim.notify(msg ~= '' and msg or 'Stashed changes', vim.log.levels.INFO)
            else
              local msg = git_util.trim_output(res)
              vim.notify('git stash failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
            end
            reload_status(ctx)
          end)
          return 'keep_open'
        end,
      },

      refresh = {
        allow_empty = true,
        desc = 'Refresh git status',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          reload_status(ctx)
          return 'keep_open'
        end,
      },
    },
  }
end

return M
