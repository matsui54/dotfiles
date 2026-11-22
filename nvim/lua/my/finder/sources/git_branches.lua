local backend = require('my.finder.backend')

local M = {}

---@param path string
---@return string|nil
local function find_git_root(path)
  local dir = (path and path ~= '') and vim.fn.fnamemodify(path, ':h') or vim.fn.getcwd()
  if vim.fn.isdirectory(dir) == 0 then
    dir = vim.fn.getcwd()
  end
  local res = vim.system({ 'git', '-C', dir, 'rev-parse', '--show-toplevel' }, { text = true }):wait()
  if res.code ~= 0 or not res.stdout then
    return nil
  end
  return vim.trim(res.stdout)
end

---@param git_args string[]
---@return string
local function format_git_cmd(git_args)
  local parts = { 'git' }
  for _, arg in ipairs(git_args) do
    local s = tostring(arg)
    if s:match('^[%w%._/%-%+=:@]+$') then
      parts[#parts + 1] = s
    else
      parts[#parts + 1] = vim.fn.shellescape(s)
    end
  end
  return table.concat(parts, ' ')
end

---@param res vim.SystemCompleted
---@return string
local function trim_output(res)
  local err = vim.trim(res.stderr or '')
  if err ~= '' then
    return err
  end
  return vim.trim(res.stdout or '')
end

---@param root string
---@param git_args string[]
---@param cb fun(res: vim.SystemCompleted)
local function run_git(root, git_args, cb)
  local cmd = { 'git', '-C', root }
  vim.list_extend(cmd, git_args)
  vim.system(cmd, { text = true }, function(res)
    vim.schedule(function()
      cb(res)
    end)
  end)
end

---@param ctx table
---@param cmds string[][]
---@param extra_note? string
---@return boolean
local function confirm_git_cmds(ctx, cmds, extra_note)
  local cmd_strs = {}
  for _, args in ipairs(cmds) do
    cmd_strs[#cmd_strs + 1] = format_git_cmd(args)
  end

  local msg
  if #cmd_strs == 1 then
    msg = 'Run: ' .. cmd_strs[1]
  else
    msg = 'Run:\n  ' .. table.concat(cmd_strs, '\n  ')
  end
  if extra_note and extra_note ~= '' then
    msg = msg .. '\n\n' .. extra_note
  end

  local choice = ctx.with_prompt(function()
    return vim.fn.confirm(msg, '&Yes\n&No', 2)
  end)
  return choice == 1
end

---@param raw string
---@return table[], string[]
local function parse_branches(raw)
  local entries = {}
  local match_texts = {}
  for _, line in ipairs(vim.split(raw, '\n', { plain = true, trimempty = true })) do
    local head, fullref, name, hash, subject = line:match('^([^\t]*)\t([^\t]+)\t([^\t]+)\t([^\t]*)\t(.*)$')
    if fullref and name and not fullref:match('^refs/remotes/[^/]+/HEAD$') and not name:match('/HEAD$') then
      local is_cur = head == '*'
      local is_remote = vim.startswith(fullref, 'refs/remotes/')
      local remote, remote_branch = nil, nil
      if is_remote then
        local rest = fullref:sub(#'refs/remotes/' + 1)
        remote, remote_branch = rest:match('^([^/]+)/(.+)$')
      end

      local prefix = is_cur and '* ' or '  '
      local display = string.format('%s%-28s  %s  %s', prefix, name, hash, subject)

      local hls = {}
      if is_cur then
        table.insert(hls, { 0, 2 + #name, 'Added' })
      end
      local hash_start = #prefix + math.max(28, #name) + 2
      if hash_start + #hash <= #display then
        table.insert(hls, { hash_start, hash_start + #hash, 'Identifier' })
      end

      entries[#entries + 1] = {
        id = 'branch:' .. fullref,
        fullref = fullref,
        branch = name,
        short_branch = is_remote and (remote_branch or name) or name,
        remote = remote,
        is_remote = is_remote,
        is_current = is_cur,
        display = display,
        highlights = hls,
        match_offset = #prefix,
      }
      match_texts[#match_texts + 1] = name
    end
  end
  return entries, match_texts
end

---@param ctx table
---@param on_done fun()
local function fetch_branches(ctx, on_done)
  ctx.fetch_gen = (ctx.fetch_gen or 0) + 1
  local gen = ctx.fetch_gen

  vim.system({
    'git',
    '-C',
    ctx.git_root,
    'for-each-ref',
    '--sort=-committerdate',
    '--format=%(HEAD)%09%(refname)%09%(refname:short)%09%(objectname:short)%09%(subject)',
    'refs/heads',
    'refs/remotes',
  }, { text = true }, function(res)
    vim.schedule(function()
      if gen ~= ctx.fetch_gen then
        return
      end
      if res.code == 0 and res.stdout then
        ctx.entries, ctx.match_texts = parse_branches(res.stdout)
      else
        ctx.entries, ctx.match_texts = {}, {}
      end
      ctx.loading = false
      on_done()
    end)
  end)
end

---@param ctx table
---@param refresh_opts? boolean|table
local function reload_branches(ctx, refresh_opts)
  if not ctx.git_root then
    return
  end
  fetch_branches(ctx, function()
    ctx.refresh(refresh_opts ~= nil and refresh_opts or true)
  end)
end

---@param targets table[]
---@param ctx table
---@param force boolean
---@return string
local function delete_local_branches(targets, ctx, force)
  local root = ctx.git_root
  if not root then
    return 'keep_open'
  end

  local local_names = {}
  local target_ids = {}
  local skipped_current = {}
  local skipped_remote = {}

  for _, it in ipairs(targets) do
    if it.is_remote then
      skipped_remote[#skipped_remote + 1] = it.branch
    elseif it.is_current then
      skipped_current[#skipped_current + 1] = it.branch
    elseif it.branch then
      local_names[#local_names + 1] = it.branch
      target_ids[#target_ids + 1] = it.id
    end
  end

  if #local_names == 0 then
    local reasons = {}
    if #skipped_current > 0 then
      reasons[#reasons + 1] = 'cannot delete current branch (' .. table.concat(skipped_current, ', ') .. ')'
    end
    if #skipped_remote > 0 then
      reasons[#reasons + 1] = 'use action "delete_remote" (via `a`) for remote branch (' .. table.concat(skipped_remote, ', ') .. ')'
    end
    vim.notify(#reasons > 0 and table.concat(reasons, '; ') or 'No local branches selected', vim.log.levels.WARN)
    return 'keep_open'
  end

  local args = { 'branch', force and '-D' or '-d' }
  vim.list_extend(args, local_names)

  local notes = {}
  if #skipped_current > 0 then
    notes[#notes + 1] = 'Skipped current: ' .. table.concat(skipped_current, ', ')
  end
  if #skipped_remote > 0 then
    notes[#notes + 1] = 'Skipped remote: ' .. table.concat(skipped_remote, ', ')
  end
  local extra_note = #notes > 0 and table.concat(notes, '\n') or nil

  if not confirm_git_cmds(ctx, { args }, extra_note) then
    return 'keep_open'
  end

  run_git(root, args, function(res)
    ctx.clear_marks(target_ids)
    if res.code == 0 then
      local msg = trim_output(res)
      vim.notify(msg ~= '' and msg or ('Deleted branch(es): ' .. table.concat(local_names, ', ')), vim.log.levels.INFO)
    else
      local msg = trim_output(res)
      vim.notify('git branch delete failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
    end
    reload_branches(ctx)
  end)

  return 'keep_open'
end

---@param targets table[]
---@param ctx table
---@return string
local function delete_remote_branches(targets, ctx)
  local root = ctx.git_root
  if not root then
    return 'keep_open'
  end

  local remote_order = {}
  local by_remote = {}
  local target_ids = {}
  local skipped_local = {}

  for _, it in ipairs(targets) do
    if it.is_remote and it.remote and it.short_branch then
      if not by_remote[it.remote] then
        by_remote[it.remote] = {}
        remote_order[#remote_order + 1] = it.remote
      end
      table.insert(by_remote[it.remote], it.short_branch)
      target_ids[#target_ids + 1] = it.id
    else
      skipped_local[#skipped_local + 1] = it.branch
    end
  end

  if #remote_order == 0 then
    vim.notify('Select remote branch(es) to delete', vim.log.levels.WARN)
    return 'keep_open'
  end

  local cmds = {}
  for _, remote in ipairs(remote_order) do
    local args = { 'push', remote, '--delete' }
    vim.list_extend(args, by_remote[remote])
    cmds[#cmds + 1] = args
  end

  local extra_note = #skipped_local > 0 and ('Skipped local: ' .. table.concat(skipped_local, ', ')) or nil
  if not confirm_git_cmds(ctx, cmds, extra_note) then
    return 'keep_open'
  end

  local errors = {}
  local idx = 1
  local function step()
    if idx > #cmds then
      ctx.clear_marks(target_ids)
      if #errors == 0 then
        vim.notify('Deleted remote branch(es)', vim.log.levels.INFO)
      else
        vim.notify('git push --delete failed:\n' .. table.concat(errors, '\n'), vim.log.levels.ERROR)
      end
      reload_branches(ctx)
      return
    end
    local args = cmds[idx]
    idx = idx + 1
    run_git(root, args, function(res)
      if res.code ~= 0 then
        local msg = trim_output(res)
        errors[#errors + 1] = format_git_cmd(args) .. (msg ~= '' and ': ' .. msg or '')
      end
      step()
    end)
  end
  step()

  return 'keep_open'
end

function M.new()
  return {
    name = 'git_branches',
    title = 'Git Branches',
    prompt = 'branch> ',
    show_preview = true,
    allow_preview = true,
    builtin_actions = {},

    prepare = function(ctx)
      local root = find_git_root(ctx.origin_path)
      return {
        git_root = root,
        entries = nil,
        match_texts = nil,
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
        local res = backend.fuzzy_match_list(query, ctx.match_texts or {}, { limit = 200 })
        local items = {}
        for _, m in ipairs(res.items or {}) do
          local src = ctx.entries[m.idx]
          if src then
            items[#items + 1] = vim.tbl_extend('force', src, {
              match_indices = m.match_indices,
              git_root = ctx.git_root,
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

      fetch_branches(ctx, function()
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
      if not item.git_root or not (item.fullref or item.branch) then
        cb({ '(no git repository)' }, { skip_ts = true })
        return
      end
      vim.system({
        'git',
        '-C',
        item.git_root,
        'log',
        '-n',
        '40',
        '--oneline',
        '--decorate',
        item.fullref or item.branch,
      }, { text = true }, function(res)
        vim.schedule(function()
          if pctx.is_stale() then
            return
          end
          if res.code ~= 0 or not res.stdout then
            cb({ 'git log failed: ' .. tostring(res.stderr or '') }, { skip_ts = true })
            return
          end
          local lines = vim.split(res.stdout, '\n', { plain = true, trimempty = true })
          if #lines == 0 then
            lines = { '(no commits)' }
          end
          cb(lines, { skip_ts = true })
        end)
      end)
    end,

    keymaps = {
      ['<CR>'] = {
        action = 'checkout',
        desc = 'Finder git_branches: checkout branch',
      },
      o = {
        action = 'new',
        desc = 'Finder git_branches: create new branch',
      },
      O = {
        action = 'new_from',
        desc = 'Finder git_branches: create branch from cursor',
      },
      dd = {
        action = 'delete',
        desc = 'Finder git_branches: delete branch (-d)',
      },
      D = {
        action = 'delete_force',
        desc = 'Finder git_branches: force delete branch (-D)',
      },
      R = {
        action = 'rename',
        desc = 'Finder git_branches: rename branch',
      },
      m = {
        action = 'merge',
        desc = 'Finder git_branches: merge branch',
      },
      r = {
        action = 'refresh',
        desc = 'Finder git_branches: refresh',
      },
    },

    actions = {
      checkout = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.branch then
          return 'keep_open'
        end
        if it.is_current then
          vim.notify('Already on branch: ' .. it.branch, vim.log.levels.INFO)
          return 'keep_open'
        end

        local function do_switch(args, label, select_ref)
          run_git(it.git_root, args, function(res)
            if res.code == 0 then
              vim.notify('Switched to branch: ' .. label, vim.log.levels.INFO)
              pcall(vim.cmd, 'checktime')
              reload_branches(ctx, { restore_cursor_id = 'branch:' .. select_ref })
            else
              local msg = trim_output(res)
              vim.notify('git switch failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
            end
          end)
        end

        if it.is_remote and it.short_branch then
          run_git(it.git_root, { 'show-ref', '--verify', '--quiet', 'refs/heads/' .. it.short_branch }, function(check)
            if check.code == 0 then
              do_switch({ 'switch', it.short_branch }, it.short_branch, 'refs/heads/' .. it.short_branch)
            else
              do_switch(
                { 'switch', '-c', it.short_branch, '--track', it.fullref },
                it.short_branch .. ' (tracking ' .. it.branch .. ')',
                'refs/heads/' .. it.short_branch
              )
            end
          end)
        else
          do_switch({ 'switch', it.branch }, it.branch, it.fullref)
        end

        return 'keep_open'
      end,

      new = {
        allow_empty = true,
        desc = 'Create and switch to a new branch from HEAD',
        fn = function(_, ctx)
          if not ctx.git_root then
            vim.notify('Not inside a git repository', vim.log.levels.WARN)
            return 'keep_open'
          end
          ctx.with_prompt(function(done)
            vim.ui.input({ prompt = 'New branch: ' }, function(input)
              done()
              if not input then
                return
              end
              local name = vim.trim(input)
              if name == '' then
                return
              end
              run_git(ctx.git_root, { 'switch', '-c', name }, function(res)
                if res.code == 0 then
                  vim.notify('Created and switched to branch: ' .. name, vim.log.levels.INFO)
                  pcall(vim.cmd, 'checktime')
                  reload_branches(ctx, { restore_cursor_id = 'branch:refs/heads/' .. name })
                else
                  local msg = trim_output(res)
                  vim.notify('git switch -c failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
                end
              end)
            end)
          end, true)
          return 'keep_open'
        end,
      },

      new_from = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.branch then
          return 'keep_open'
        end
        ctx.with_prompt(function(done)
          vim.ui.input({ prompt = string.format('New branch (from %s): ', it.branch) }, function(input)
            done()
            if not input then
              return
            end
            local name = vim.trim(input)
            if name == '' then
              return
            end
            run_git(it.git_root, { 'switch', '-c', name, '--no-track', it.fullref or it.branch }, function(res)
              if res.code == 0 then
                vim.notify('Created and switched to branch: ' .. name .. ' (from ' .. it.branch .. ')', vim.log.levels.INFO)
                pcall(vim.cmd, 'checktime')
                reload_branches(ctx, { restore_cursor_id = 'branch:refs/heads/' .. name })
              else
                local msg = trim_output(res)
                vim.notify('git switch -c failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
              end
            end)
          end)
        end, true)
        return 'keep_open'
      end,

      delete = function(targets, ctx)
        return delete_local_branches(targets, ctx, false)
      end,

      delete_force = function(targets, ctx)
        return delete_local_branches(targets, ctx, true)
      end,

      delete_remote = function(targets, ctx)
        return delete_remote_branches(targets, ctx)
      end,

      rename = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.branch then
          return 'keep_open'
        end
        if it.is_remote then
          vim.notify('Cannot rename remote branch: ' .. it.branch, vim.log.levels.WARN)
          return 'keep_open'
        end
        ctx.with_prompt(function(done)
          vim.ui.input({ prompt = string.format('Rename %s to: ', it.branch), default = it.branch }, function(input)
            done()
            if not input then
              return
            end
            local new_name = vim.trim(input)
            if new_name == '' or new_name == it.branch then
              return
            end
            run_git(it.git_root, { 'branch', '-m', it.branch, new_name }, function(res)
              if res.code == 0 then
                vim.notify('Renamed branch: ' .. it.branch .. ' -> ' .. new_name, vim.log.levels.INFO)
                ctx.clear_marks({ it.id })
                reload_branches(ctx, { restore_cursor_id = 'branch:refs/heads/' .. new_name })
              else
                local msg = trim_output(res)
                vim.notify('git branch -m failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
              end
            end)
          end)
        end, true)
        return 'keep_open'
      end,

      merge = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.branch then
          return 'keep_open'
        end
        if it.is_current then
          vim.notify('Cannot merge current branch into itself', vim.log.levels.WARN)
          return 'keep_open'
        end
        local args = { 'merge', it.branch }
        if not confirm_git_cmds(ctx, { args }) then
          return 'keep_open'
        end
        run_git(it.git_root, args, function(res)
          pcall(vim.cmd, 'checktime')
          if res.code == 0 then
            local msg = trim_output(res)
            vim.notify(msg ~= '' and msg or ('Merged ' .. it.branch), vim.log.levels.INFO)
          else
            local msg = trim_output(res)
            vim.notify('git merge failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_branches(ctx)
        end)
        return 'keep_open'
      end,

      rebase = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.branch then
          return 'keep_open'
        end
        if it.is_current then
          vim.notify('Cannot rebase current branch onto itself', vim.log.levels.WARN)
          return 'keep_open'
        end
        local args = { 'rebase', it.branch }
        if not confirm_git_cmds(ctx, { args }) then
          return 'keep_open'
        end
        run_git(it.git_root, args, function(res)
          pcall(vim.cmd, 'checktime')
          if res.code == 0 then
            local msg = trim_output(res)
            vim.notify(msg ~= '' and msg or ('Rebased onto ' .. it.branch), vim.log.levels.INFO)
          else
            local msg = trim_output(res)
            vim.notify('git rebase failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_branches(ctx)
        end)
        return 'keep_open'
      end,

      fetch = {
        allow_empty = true,
        desc = 'Run git fetch --prune',
        fn = function(_, ctx)
          if not ctx.git_root then
            vim.notify('Not inside a git repository', vim.log.levels.WARN)
            return 'keep_open'
          end
          vim.notify('Running: git fetch --prune...', vim.log.levels.INFO)
          run_git(ctx.git_root, { 'fetch', '--prune' }, function(res)
            if res.code == 0 then
              local msg = trim_output(res)
              vim.notify(msg ~= '' and msg or 'git fetch --prune completed', vim.log.levels.INFO)
            else
              local msg = trim_output(res)
              vim.notify('git fetch failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
            end
            reload_branches(ctx)
          end)
          return 'keep_open'
        end,
      },

      refresh = {
        allow_empty = true,
        desc = 'Refresh branch list',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          reload_branches(ctx)
          return 'keep_open'
        end,
      },
    },
  }
end

return M
