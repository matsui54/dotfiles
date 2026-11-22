local backend = require('my.finder.backend')
local git_util = require('my.finder.git_util')
local ui = require('my.finder.ui')

local M = {}

local PAGE_SIZE = 100
local MAX_PREVIEW_LINES = 1500

---@param root string|nil
---@param abs_path string|nil
---@return string|nil
local function to_rel_path(root, abs_path)
  if not root or not abs_path or abs_path == '' or abs_path:match('^%a[%w+.-]*://') then
    return nil
  end
  local norm_root = vim.fs.normalize(root)
  local norm_file = vim.fs.normalize(abs_path)
  if norm_file:sub(1, #norm_root + 1) == norm_root .. '/' then
    return norm_file:sub(#norm_root + 2)
  end
  return nil
end

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
  end
  return 'Normal'
end

---@param raw string
---@return table[], string[]
local function parse_commits(raw)
  local entries = {}
  local match_texts = {}
  local records = vim.split(raw, '\x1e', { plain = true, trimempty = true })

  for _, rec in ipairs(records) do
    local fields = vim.split(rec, '\0', { plain = true })
    if #fields >= 6 then
      local hash = vim.trim(fields[1])
      if hash ~= '' then
        local short = fields[2] or ''
        local date = fields[3] or ''
        local author = fields[4] or ''
        local refs = vim.trim(fields[5] or '')
        local subject = fields[6] or ''
        local parents = vim.trim(fields[7] or '')

        local refs_str = (refs ~= '') and (' ' .. refs) or ''
        local display = string.format('%s  %s  %s%s  %s', short, date, author, refs_str, subject)

        local hash_start = 0
        local hash_end = #short
        local date_start = hash_end + 2
        local date_end = date_start + #date
        local author_start = date_end + 2
        local author_end = author_start + #author

        local hls = {
          { hash_start, hash_end, 'Identifier' },
          { date_start, date_end, 'Comment' },
          { author_start, author_end, 'Type' },
        }
        if refs_str ~= '' then
          local refs_start = author_end + 1
          local refs_end = refs_start + #refs
          hls[#hls + 1] = { refs_start, refs_end, 'Special' }
        end

        entries[#entries + 1] = {
          id = 'commit:' .. hash,
          hash = hash,
          short = short,
          date = date,
          author = author,
          refs = refs,
          subject = subject,
          parents = parents,
          has_parent = parents ~= '',
          display = display,
          highlights = hls,
          match_offset = 0,
        }
        match_texts[#match_texts + 1] = display
      end
    end
  end

  return entries, match_texts
end

---@param raw string
---@param root string
---@return table[], string[]
local function parse_name_status(raw, root)
  local entries = {}
  local match_texts = {}
  local items = vim.split(raw, '\0', { plain = true, trimempty = true })
  local i = 1

  while i <= #items do
    local code = items[i]
    local c1 = code:sub(1, 1)
    local orig_path = nil
    local rel_path = nil

    if (c1 == 'R' or c1 == 'C') and i + 2 <= #items then
      orig_path = items[i + 1]
      rel_path = items[i + 2]
      i = i + 3
    elseif i + 1 <= #items then
      rel_path = items[i + 1]
      i = i + 2
    else
      break
    end

    if rel_path and rel_path ~= '' then
      local display_path = orig_path and (orig_path .. ' -> ' .. rel_path) or rel_path
      local display = string.format('%s  %s', c1, display_path)
      entries[#entries + 1] = {
        id = 'file:' .. rel_path,
        code = c1,
        rel_path = rel_path,
        orig_path = orig_path,
        path = root .. '/' .. rel_path,
        git_root = root,
        display = display,
        highlights = { { 0, 1, hl_for_code(c1) } },
        match_offset = 3,
      }
      match_texts[#match_texts + 1] = display_path
    end
  end

  return entries, match_texts
end

---@param ctx table
---@return string
local function build_log_prompt(ctx)
  local branch = ctx.branch or '...'
  if ctx.line_range and ctx.origin_file then
    return string.format('log [%s] (L%d-%d:%s)> ', branch, ctx.line_range[1], ctx.line_range[2], ctx.origin_file)
  elseif ctx.filter_file and ctx.origin_file then
    return string.format('log [%s] (%s)> ', branch, ctx.origin_file)
  end
  return string.format('log [%s]> ', branch)
end

---@param ctx table
---@param on_done fun()
local function fetch_files(ctx, on_done)
  ctx.fetch_gen = (ctx.fetch_gen or 0) + 1
  local gen = ctx.fetch_gen

  git_util.run_git(ctx.git_root, ctx.fetch_args, function(res)
    if gen ~= ctx.fetch_gen then
      return
    end
    if res.code == 0 and res.stdout then
      ctx.entries, ctx.match_texts = parse_name_status(res.stdout, ctx.git_root)
    else
      ctx.entries, ctx.match_texts = {}, {}
      local msg = git_util.trim_output(res)
      if msg ~= '' then
        vim.notify('git diff failed: ' .. msg, vim.log.levels.ERROR)
      end
    end
    ctx.loading = false
    on_done()
  end, { text = false })
end

---@param spec { git_root: string, title: string, prompt: string, base_ref: string|nil, target_ref: string|nil, fetch_args: string[], parent_snapshot: table }
---@return table
local function new_files_source(spec)
  local function reload_files(ctx)
    if not ctx.git_root then
      return
    end
    fetch_files(ctx, function()
      ctx.refresh(true)
    end)
  end

  return {
    name = 'git_log_files',
    title = spec.title,
    prompt = spec.prompt,
    scanning_hint = '  Loading...',
    empty_hint = '  (no changed files)',
    show_preview = true,
    allow_preview = true,

    prepare = function()
      return {
        git_root = spec.git_root,
        fetch_args = spec.fetch_args,
        entries = nil,
        match_texts = nil,
        loading = true,
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
        local res = backend.fuzzy_match_list(query, ctx.match_texts or {}, {
          limit = math.max(500, ctx.limit or PAGE_SIZE),
        })
        local items = {}
        for _, m in ipairs(res.items or {}) do
          local src = ctx.entries[m.idx]
          if src then
            items[#items + 1] = vim.tbl_extend('force', src, {
              match_indices = m.match_indices,
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

      fetch_files(ctx, function()
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

      local args
      if spec.target_ref == 'WORKTREE' then
        args = { 'diff', '--no-color', spec.base_ref, '--' }
      elseif not spec.base_ref then
        args = { 'show', '--no-color', '--format=', spec.target_ref, '--' }
      else
        args = { 'diff', '--no-color', spec.base_ref, spec.target_ref, '--' }
      end
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
        while #lines > 0 and lines[1] == '' do
          table.remove(lines, 1)
        end
        if #lines > 1 and lines[#lines] == '' then
          table.remove(lines, #lines)
        end
        if #lines == 0 then
          cb({ '(no diff)' }, { skip_ts = true })
          return
        end
        if #lines > MAX_PREVIEW_LINES then
          local truncated = {}
          for i = 1, MAX_PREVIEW_LINES do
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
        desc = 'Finder git_log_files: open diffthis tab',
      },
      ['<BS>'] = {
        action = 'back',
        desc = 'Finder git_log_files: back to git log',
      },
      ['-'] = {
        action = 'back',
        desc = 'Finder git_log_files: back to git log',
      },
      r = {
        action = 'refresh',
        desc = 'Finder git_log_files: refresh',
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
          git_util.open_commit_diff_tab(it.git_root, spec.base_ref, spec.target_ref, it, entries, false)
        end)
      end,

      back = {
        allow_empty = true,
        desc = 'Return to git commit log',
        fn = function()
          local snap = spec.parent_snapshot
          local parent_opts = { _snapshot = snap }
          if snap.ui_opts then
            for k, v in pairs(snap.ui_opts) do
              parent_opts[k] = v
            end
          end
          ui.open(M.new(), parent_opts)
          return 'keep_open'
        end,
      },

      refresh = {
        allow_empty = true,
        desc = 'Refresh changed files',
        fn = function(_, ctx)
          reload_files(ctx)
          return 'keep_open'
        end,
      },
    },
  }
end

---@param ctx table
---@param on_done fun()
local function fetch_log(ctx, on_done)
  ctx.fetch_gen = (ctx.fetch_gen or 0) + 1
  local gen = ctx.fetch_gen
  local pending = 2

  local function finish_one()
    pending = pending - 1
    if pending == 0 then
      ctx.prompt = build_log_prompt(ctx)
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
    finish_one()
  end)

  local args = {
    'log',
    '--max-count=' .. tostring(ctx.limit or PAGE_SIZE),
    '--date=short',
    '--format=%H%x00%h%x00%ad%x00%an%x00%d%x00%s%x00%P%x1e',
  }
  if ctx.line_range and ctx.origin_file then
    args[#args + 1] = '--no-patch'
    args[#args + 1] = string.format('-L%d,%d:%s', ctx.line_range[1], ctx.line_range[2], ctx.origin_file)
  elseif ctx.filter_file and ctx.origin_file then
    args[#args + 1] = '--'
    args[#args + 1] = ctx.origin_file
  end

  git_util.run_git(ctx.git_root, args, function(res)
    if gen ~= ctx.fetch_gen then
      return
    end
    if res.code == 0 and res.stdout then
      ctx.entries, ctx.match_texts = parse_commits(res.stdout)
    else
      ctx.entries, ctx.match_texts = {}, {}
      local msg = git_util.trim_output(res)
      if msg ~= '' then
        vim.notify('git log failed: ' .. msg, vim.log.levels.ERROR)
      end
    end
    finish_one()
  end, { text = false })
end

---@param ctx table
---@param refresh_opts? boolean|table
local function reload_log(ctx, refresh_opts)
  if not ctx.git_root then
    return
  end
  fetch_log(ctx, function()
    ctx.refresh(refresh_opts ~= nil and refresh_opts or true)
  end)
end

---@param ctx table
---@return table
local function make_parent_snapshot(ctx)
  return {
    git_root = ctx.git_root,
    branch = ctx.branch,
    origin_file = ctx.origin_file,
    filter_file = ctx.filter_file,
    line_range = ctx.line_range,
    limit = ctx.limit,
    entries = ctx.entries,
    match_texts = ctx.match_texts,
    prompt = ctx.prompt,
    ui_opts = {
      query = ctx.query,
      marked = ctx.get_marks(),
      restore_cursor_id = ctx.get_cursor_id(),
      preview_enabled = ctx.get_preview_enabled(),
    },
  }
end

---@param targets table[]
---@param ctx table
---@return table[]
local function sort_targets_chronological_oldest_first(targets, ctx)
  local index_of = {}
  for i, e in ipairs(ctx.entries or {}) do
    index_of[e.hash] = i
  end
  local ordered = {}
  for _, it in ipairs(targets) do
    if it.hash then
      ordered[#ordered + 1] = it
    end
  end
  table.sort(ordered, function(a, b)
    return (index_of[a.hash] or 0) > (index_of[b.hash] or 0)
  end)
  return ordered
end

---@return table
function M.new()
  return {
    name = 'git_log',
    title = 'Git Log',
    prompt = 'log> ',
    scanning_hint = '  Loading...',
    empty_hint = '  (no commits)',
    show_preview = true,
    allow_preview = true,
    builtin_actions = {},

    prepare = function(ctx, open_opts)
      local snap = open_opts and open_opts._snapshot
      if type(snap) == 'table' then
        open_opts._snapshot = nil
        open_opts.git_root = snap.git_root
        open_opts.filter_file = snap.filter_file
        open_opts.line_range = snap.line_range
        open_opts.limit = snap.limit or PAGE_SIZE
        if snap.git_root and snap.origin_file then
          open_opts.file = snap.git_root .. '/' .. snap.origin_file
        end
        return {
          git_root = snap.git_root,
          branch = snap.branch,
          origin_file = snap.origin_file,
          filter_file = snap.filter_file,
          line_range = snap.line_range,
          limit = snap.limit or PAGE_SIZE,
          entries = snap.entries,
          match_texts = snap.match_texts,
          prompt = snap.prompt,
          loading = snap.entries == nil and snap.git_root ~= nil,
          fetch_gen = 0,
        }
      end

      local target_file = (open_opts and open_opts.file) or ctx.origin_path
      local root = (open_opts and open_opts.git_root) or git_util.find_git_root(target_file)
      local rel = to_rel_path(root, target_file)
      local line_range = open_opts and open_opts.line_range or nil
      local filter_file = (line_range ~= nil and rel ~= nil) or (open_opts and open_opts.filter_file == true and rel ~= nil)
      return {
        git_root = root,
        branch = nil,
        origin_file = rel,
        filter_file = filter_file,
        line_range = line_range,
        limit = (open_opts and open_opts.limit) or PAGE_SIZE,
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
        local res = backend.fuzzy_match_list(query, ctx.match_texts or {}, {
          limit = math.max(500, ctx.limit or PAGE_SIZE),
        })
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

      fetch_log(ctx, function()
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
      if not item.git_root or not item.hash then
        cb({ '(no commit)' }, { skip_ts = true })
        return
      end

      git_util.run_git(
        item.git_root,
        { 'show', '--format=fuller', '--stat', '--patch', '--no-color', item.hash },
        function(res)
          if pctx.is_stale() then
            return
          end
          if res.code ~= 0 then
            local msg = git_util.trim_output(res)
            cb({ 'git show failed' .. (msg ~= '' and ': ' .. msg or '') }, { skip_ts = true })
            return
          end
          local lines = vim.split(res.stdout or '', '\n', { plain = true })
          if #lines > 1 and lines[#lines] == '' then
            table.remove(lines, #lines)
          end
          if #lines == 0 then
            cb({ '(empty commit)' }, { skip_ts = true })
            return
          end
          if #lines > MAX_PREVIEW_LINES then
            local truncated = {}
            for i = 1, MAX_PREVIEW_LINES do
              truncated[i] = lines[i]
            end
            truncated[#truncated + 1] = string.format('... [output truncated, total %d lines] ...', #lines)
            lines = truncated
          end
          local hls = git_util.highlight_commit_show_lines(lines)
          cb(lines, { skip_ts = true, highlights = hls })
        end,
        { text = false }
      )
    end,

    keymaps = {
      ['<CR>'] = {
        action = 'files',
        desc = 'Finder git_log: open commit changed files',
      },
      ['<Tab>'] = {
        action = 'files',
        desc = 'Finder git_log: open commit changed files',
      },
      d = {
        action = 'compare',
        desc = 'Finder git_log: compare commits',
      },
      y = {
        action = 'yank_hash',
        desc = 'Finder git_log: yank commit hash',
      },
      F = {
        action = 'toggle_file_filter',
        desc = 'Finder git_log: toggle current file filter',
      },
      ['+'] = {
        action = 'load_more',
        desc = 'Finder git_log: load more commits',
      },
      r = {
        action = 'refresh',
        desc = 'Finder git_log: refresh',
      },
    },

    actions = {
      files = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        local base_ref = it.has_parent and (it.hash .. '^') or nil
        local snap = make_parent_snapshot(ctx)
        local child = new_files_source({
          git_root = it.git_root,
          title = 'Commit ' .. it.short,
          prompt = string.format('files [%s]> ', it.short),
          base_ref = base_ref,
          target_ref = it.hash,
          fetch_args = { 'diff-tree', '--no-commit-id', '--name-status', '-r', '-z', '--root', '--first-parent', it.hash },
          parent_snapshot = snap,
        })
        ui.open(child, { preview_enabled = ctx.get_preview_enabled() })
        return 'keep_open'
      end,

      compare = function(targets, ctx)
        if not ctx.git_root then
          return 'keep_open'
        end
        if #targets > 2 then
          vim.notify('Mark 1 or 2 commits with "," to compare', vim.log.levels.WARN)
          return 'keep_open'
        end

        local base, target, base_short, target_short, fetch_args
        if #targets == 1 then
          base = targets[1].hash
          target = 'WORKTREE'
          base_short = targets[1].short
          target_short = 'WORKTREE'
          fetch_args = { 'diff', '--name-status', '-z', base }
        else
          local ordered = sort_targets_chronological_oldest_first(targets, ctx)
          base = ordered[1].hash
          target = ordered[2].hash
          base_short = ordered[1].short
          target_short = ordered[2].short
          fetch_args = { 'diff', '--name-status', '-z', base, target }
        end

        local snap = make_parent_snapshot(ctx)
        local child = new_files_source({
          git_root = ctx.git_root,
          title = string.format('Diff %s..%s', base_short, target_short),
          prompt = string.format('diff [%s..%s]> ', base_short, target_short),
          base_ref = base,
          target_ref = target,
          fetch_args = fetch_args,
          parent_snapshot = snap,
        })
        ui.open(child, { preview_enabled = ctx.get_preview_enabled() })
        return 'keep_open'
      end,

      yank_hash = function(targets)
        local it = targets[1]
        if it and it.hash then
          vim.fn.setreg('"', it.hash)
          pcall(vim.fn.setreg, '+', it.hash)
          vim.notify('Copied ' .. it.hash, vim.log.levels.INFO)
        end
        return 'keep_open'
      end,

      yank_short = function(targets)
        local it = targets[1]
        if it and it.short then
          vim.fn.setreg('"', it.short)
          pcall(vim.fn.setreg, '+', it.short)
          vim.notify('Copied ' .. it.short, vim.log.levels.INFO)
        end
        return 'keep_open'
      end,

      toggle_file_filter = {
        allow_empty = true,
        desc = 'Toggle current file history filter',
        fn = function(_, ctx)
          if not ctx.origin_file then
            vim.notify('No origin file to filter by', vim.log.levels.INFO)
            return 'keep_open'
          end
          ctx.line_range = nil
          ctx.filter_file = not ctx.filter_file
          reload_log(ctx, true)
          return 'keep_open'
        end,
      },

      load_more = {
        allow_empty = true,
        desc = 'Load more commits (+100)',
        fn = function(_, ctx)
          if not ctx.git_root then
            return 'keep_open'
          end
          ctx.limit = (ctx.limit or PAGE_SIZE) + PAGE_SIZE
          reload_log(ctx, true)
          return 'keep_open'
        end,
      },

      refresh = {
        allow_empty = true,
        desc = 'Refresh git log',
        fn = function(_, ctx)
          reload_log(ctx, true)
          return 'keep_open'
        end,
      },

      checkout = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        local args = { 'switch', '--detach', it.short }
        if not git_util.confirm_git_cmds(ctx, { args }) then
          return 'keep_open'
        end
        git_util.run_git(it.git_root, { 'switch', '--detach', it.hash }, function(res)
          pcall(vim.cmd, 'checktime')
          if res.code == 0 then
            vim.notify('Checked out detached HEAD: ' .. it.short, vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git switch --detach failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,

      new_branch = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        ctx.with_prompt(function(done)
          vim.ui.input({ prompt = string.format('New branch (from %s): ', it.short) }, function(input)
            done()
            if not input then
              return
            end
            local name = vim.trim(input)
            if name == '' then
              return
            end
            git_util.run_git(it.git_root, { 'switch', '-c', name, it.hash }, function(res)
              pcall(vim.cmd, 'checktime')
              if res.code == 0 then
                vim.notify('Created and switched to branch: ' .. name .. ' (from ' .. it.short .. ')', vim.log.levels.INFO)
              else
                local msg = git_util.trim_output(res)
                vim.notify('git switch -c failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
              end
              reload_log(ctx, true)
            end)
          end)
        end, true)
        return 'keep_open'
      end,

      cherry_pick = function(targets, ctx)
        if not ctx.git_root then
          return 'keep_open'
        end
        local ordered = sort_targets_chronological_oldest_first(targets, ctx)
        if #ordered == 0 then
          return 'keep_open'
        end
        local shorts = {}
        local hashes = {}
        local ids = {}
        for _, it in ipairs(ordered) do
          shorts[#shorts + 1] = it.short
          hashes[#hashes + 1] = it.hash
          ids[#ids + 1] = it.id
        end
        local display_args = { 'cherry-pick' }
        vim.list_extend(display_args, shorts)
        if not git_util.confirm_git_cmds(ctx, { display_args }) then
          return 'keep_open'
        end
        local exec_args = { 'cherry-pick' }
        vim.list_extend(exec_args, hashes)
        git_util.run_git(ctx.git_root, exec_args, function(res)
          pcall(vim.cmd, 'checktime')
          ctx.clear_marks(ids)
          if res.code == 0 then
            vim.notify('Cherry-picked: ' .. table.concat(shorts, ' '), vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git cherry-pick failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,

      revert = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        if not git_util.confirm_git_cmds(ctx, { { 'revert', '--no-edit', it.short } }) then
          return 'keep_open'
        end
        git_util.run_git(it.git_root, { 'revert', '--no-edit', it.hash }, function(res)
          pcall(vim.cmd, 'checktime')
          if res.code == 0 then
            vim.notify('Reverted commit: ' .. it.short, vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git revert failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,

      reset_soft = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        if not git_util.confirm_git_cmds(ctx, { { 'reset', '--soft', it.short } }) then
          return 'keep_open'
        end
        git_util.run_git(it.git_root, { 'reset', '--soft', it.hash }, function(res)
          if res.code == 0 then
            vim.notify('git reset --soft ' .. it.short, vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git reset --soft failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,

      reset_mixed = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        if not git_util.confirm_git_cmds(ctx, { { 'reset', '--mixed', it.short } }) then
          return 'keep_open'
        end
        git_util.run_git(it.git_root, { 'reset', '--mixed', it.hash }, function(res)
          if res.code == 0 then
            vim.notify('git reset --mixed ' .. it.short, vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git reset --mixed failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,

      reset_hard = function(targets, ctx)
        local it = targets[1]
        if not it or not it.git_root or not it.hash then
          return 'keep_open'
        end
        if not git_util.confirm_git_cmds(ctx, { { 'reset', '--hard', it.short } }) then
          return 'keep_open'
        end
        git_util.run_git(it.git_root, { 'reset', '--hard', it.hash }, function(res)
          pcall(vim.cmd, 'checktime')
          if res.code == 0 then
            vim.notify('git reset --hard ' .. it.short, vim.log.levels.INFO)
          else
            local msg = git_util.trim_output(res)
            vim.notify('git reset --hard failed' .. (msg ~= '' and ': ' .. msg or ''), vim.log.levels.ERROR)
          end
          reload_log(ctx, true)
        end)
        return 'keep_open'
      end,
    },
  }
end

return M
