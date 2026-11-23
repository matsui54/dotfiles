local backend = require('my.finder.backend')
local git_util = require('my.finder.git_util')
local ui = require('my.finder.ui')

local M = {}

local DEFAULT_STREAM_CAP = 200000
local LOAD_MORE_STEP = 200000
local DISPLAY_PAGE_SIZE = 200
local QUERY_DISPLAY_LIMIT = 200
local FILES_MATCH_LIMIT = 500
local SCROLL_PREFETCH_MARGIN = 30
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

---@param rec string
---@param git_root string|nil
---@return table|nil, string|nil
local function parse_commit_record(rec, git_root)
  local fields = vim.split(rec, '\0', { plain = true })
  if #fields < 6 then
    return nil, nil
  end
  local hash = vim.trim(fields[1])
  if hash == '' then
    return nil, nil
  end

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

  local entry = {
    id = 'commit:' .. hash,
    git_root = git_root,
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
  return entry, display
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
          limit = math.max(FILES_MATCH_LIMIT, ctx.limit or FILES_MATCH_LIMIT),
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
        fn = function(_, ctx)
          ctx.returning_to_parent = true
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

    on_close = function(ctx)
      if ctx.returning_to_parent then
        return
      end
      local snap = spec.parent_snapshot
      if snap and snap.session_id then
        backend.git_log_cancel(snap.session_id, { only_if_scanning = true })
      end
    end,
  }
end

---@param it table
---@param git_root string
---@return table
local function convert_rust_item(it, git_root)
  local hls = {
    { 0, it.short_len, 'Identifier' },
    { it.date_start, it.date_end, 'Comment' },
    { it.author_start, it.author_end, 'Type' },
  }
  if it.refs_end and it.refs_end > it.refs_start then
    hls[#hls + 1] = { it.refs_start, it.refs_end, 'Special' }
  end
  return {
    id = 'commit:' .. it.hash,
    git_root = git_root,
    order_idx = it.order_idx,
    hash = it.hash,
    short = it.short,
    has_parent = it.has_parent,
    display = it.display,
    highlights = hls,
    match_offset = 0,
    match_indices = (it.match_indices and #it.match_indices > 0) and it.match_indices or nil,
  }
end

---@param ctx table
---@param opts? { force?: boolean }
---@return table|nil, string|nil
local function open_log_session(ctx, opts)
  if not ctx.git_root or ctx.git_root == '' then
    return nil, 'not a git repository'
  end
  opts = opts or {}
  local open_args = {
    root = ctx.git_root,
    filter_file = (ctx.line_range ~= nil or ctx.filter_file) and ctx.origin_file or nil,
    line_range = ctx.line_range,
    limit = ctx.explicit_limit,
    force = opts.force == true,
  }
  return backend.git_log_open(open_args)
end

---@param ctx table
---@param refresh_opts? boolean|table
local function reload_log(ctx, refresh_opts)
  if not ctx.git_root then
    return
  end
  local opened, err = open_log_session(ctx, { force = true })
  if not opened then
    if err and err ~= '' then
      vim.notify('git log failed: ' .. err, vim.log.levels.ERROR)
    end
    return
  end

  if refresh_opts ~= false and ctx.get_cursor_id then
    ctx.pending_restore_id = ctx.get_cursor_id()
  else
    ctx.pending_restore_id = nil
  end
  ctx.pending_restore_line = nil
  ctx.keep_stale_on_reload = ctx.last_response ~= nil
  ctx.session_id = opened.session_id
  ctx.branch = opened.branch
  ctx.prompt = build_log_prompt(ctx)
  ctx.loading = opened.scanning == true
  ctx.has_more = opened.has_more == true
  ctx.last_revision = -1
  ctx.notified_error = nil
  ctx.pending_force_preview = true

  if ctx.refresh then
    ctx.refresh({
      preserve_cursor = refresh_opts ~= false,
      force_preview = not ctx.keep_stale_on_reload,
    })
  end
end

---@param ctx table
---@return table
local function make_parent_snapshot(ctx)
  return {
    session_id = ctx.session_id,
    git_root = ctx.git_root,
    branch = ctx.branch,
    origin_file = ctx.origin_file,
    filter_file = ctx.filter_file,
    line_range = ctx.line_range,
    explicit_limit = ctx.explicit_limit,
    load_step = ctx.load_step,
    display_limit = ctx.display_limit,
    prompt = ctx.prompt,
    has_more = ctx.has_more == true,
    ui_opts = {
      query = ctx.query,
      marked = ctx.get_marks(),
      restore_cursor_id = ctx.get_cursor_id(),
      preview_enabled = ctx.get_preview_enabled(),
    },
  }
end

---@param targets table[]
---@return table[]
local function sort_targets_chronological_oldest_first(targets)
  local ordered = {}
  for _, it in ipairs(targets) do
    if it.hash then
      ordered[#ordered + 1] = it
    end
  end
  table.sort(ordered, function(a, b)
    return (a.order_idx or 0) > (b.order_idx or 0)
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
    poll_scan = true,
    debounce_ms = 15,
    builtin_actions = {},

    prepare = function(ctx, open_opts)
      local snap = open_opts and open_opts._snapshot
      if type(snap) == 'table' then
        open_opts._snapshot = nil
        open_opts.git_root = snap.git_root
        open_opts.filter_file = snap.filter_file
        open_opts.line_range = snap.line_range
        open_opts.limit = snap.explicit_limit
        open_opts.load_step = snap.load_step
        open_opts.display_limit = snap.display_limit
        if snap.git_root and snap.origin_file then
          open_opts.file = snap.git_root .. '/' .. snap.origin_file
        end

        local res_ctx = {
          git_root = snap.git_root,
          branch = snap.branch,
          origin_file = snap.origin_file,
          filter_file = snap.filter_file,
          line_range = snap.line_range,
          explicit_limit = snap.explicit_limit,
          load_step = snap.load_step or LOAD_MORE_STEP,
          display_limit = math.max(snap.display_limit or DISPLAY_PAGE_SIZE, (open_opts and open_opts.restore_cursor_line or 0) + DISPLAY_PAGE_SIZE),
          session_id = nil,
          has_more = snap.has_more == true,
          loading = false,
          prompt = snap.prompt,
          last_revision = -1,
          last_query = nil,
          last_limit = nil,
          last_response = nil,
          keep_stale_on_reload = false,
          pending_restore_id = nil,
          pending_restore_line = nil,
          pending_force_preview = false,
          restore_query = (open_opts and open_opts.query) or '',
          notified_error = nil,
          drilling_down = false,
        }

        if snap.session_id then
          local st = backend.git_log_status(snap.session_id)
          if st and st.exists then
            res_ctx.session_id = snap.session_id
            res_ctx.loading = st.scanning == true
            res_ctx.has_more = st.has_more == true
          end
        end

        if not res_ctx.session_id and res_ctx.git_root then
          local opened, err = open_log_session(res_ctx, { force = false })
          if opened then
            res_ctx.session_id = opened.session_id
            res_ctx.branch = opened.branch
            res_ctx.prompt = build_log_prompt(res_ctx)
            res_ctx.loading = opened.scanning == true
            res_ctx.has_more = opened.has_more == true
          elseif err and err ~= '' then
            vim.notify('git log failed: ' .. err, vim.log.levels.ERROR)
          end
        end

        return res_ctx
      end

      local target_file = (open_opts and open_opts.file) or ctx.origin_path
      local root = (open_opts and open_opts.git_root) or git_util.find_git_root(target_file)
      local rel = to_rel_path(root, target_file)
      local line_range = open_opts and open_opts.line_range or nil
      local filter_file = (line_range ~= nil and rel ~= nil) or (open_opts and open_opts.filter_file == true and rel ~= nil)
      local restore_line = open_opts and open_opts.restore_cursor_line or 0
      local explicit_limit = open_opts and open_opts.limit or nil
      local display_limit = math.max((open_opts and open_opts.display_limit) or DISPLAY_PAGE_SIZE, restore_line + DISPLAY_PAGE_SIZE)

      local out_ctx = {
        git_root = root,
        branch = nil,
        origin_file = rel,
        filter_file = filter_file,
        line_range = line_range,
        explicit_limit = explicit_limit,
        load_step = (open_opts and open_opts.load_step) or LOAD_MORE_STEP,
        display_limit = display_limit,
        session_id = nil,
        has_more = false,
        loading = false,
        prompt = nil,
        last_revision = -1,
        last_query = nil,
        last_limit = nil,
        last_response = nil,
        keep_stale_on_reload = false,
        pending_restore_id = open_opts and open_opts.restore_cursor_id or nil,
        pending_restore_line = open_opts and open_opts.restore_cursor_line or nil,
        pending_force_preview = false,
        restore_query = (open_opts and open_opts.query) or '',
        notified_error = nil,
        drilling_down = false,
      }

      if root then
        local opened, err = open_log_session(out_ctx, { force = false })
        if opened then
          out_ctx.session_id = opened.session_id
          out_ctx.branch = opened.branch
          out_ctx.prompt = build_log_prompt(out_ctx)
          out_ctx.loading = opened.scanning == true
          out_ctx.has_more = opened.has_more == true
        elseif err and err ~= '' then
          vim.notify('git log failed: ' .. err, vim.log.levels.ERROR)
        end
      end

      return out_ctx
    end,

    search = function(query, ctx, _, search_opts)
      if not ctx.git_root or not ctx.session_id then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
          has_more = false,
        }
      end

      local q = query or ''
      if q ~= (ctx.restore_query or '') then
        ctx.pending_restore_id = nil
        ctx.pending_restore_line = nil
      end
      if ctx.last_query ~= nil and q ~= ctx.last_query then
        ctx.keep_stale_on_reload = false
      end

      local is_nonempty = vim.trim(q) ~= ''
      local limit = is_nonempty and QUERY_DISPLAY_LIMIT or (ctx.display_limit or DISPLAY_PAGE_SIZE)

      local st = backend.git_log_status(ctx.session_id)
      if st and not st.exists then
        local opened, err = open_log_session(ctx, { force = false })
        if opened then
          ctx.session_id = opened.session_id
          ctx.branch = opened.branch
          ctx.prompt = build_log_prompt(ctx)
          ctx.last_revision = -1
          st = backend.git_log_status(ctx.session_id)
        else
          if err and err ~= '' and ctx.notified_error ~= err then
            ctx.notified_error = err
            vim.notify('git log failed: ' .. err, vim.log.levels.ERROR)
          end
          return {
            items = {},
            total_matched = 0,
            total_items = 0,
            scanning = false,
            has_more = false,
          }
        end
      end

      if ctx.keep_stale_on_reload and ctx.last_response then
        if st and st.scanning and (st.total_items or 0) == 0 then
          return vim.tbl_extend('force', ctx.last_response, { scanning = true })
        end
        ctx.keep_stale_on_reload = false
      end

      local is_poll = search_opts and search_opts.is_poll == true
      if is_poll and st and st.scanning and st.revision == ctx.last_revision and q == ctx.last_query and limit == ctx.last_limit then
        return nil
      end

      local res, err = backend.git_log_search(ctx.session_id, q, { limit = limit, offset = 0 })
      if not res then
        if err and err ~= '' and ctx.notified_error ~= err then
          ctx.notified_error = err
          vim.notify('git log search failed: ' .. err, vim.log.levels.ERROR)
        end
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
          has_more = false,
        }
      end

      if res.error and res.error ~= '' and ctx.notified_error ~= res.error then
        ctx.notified_error = res.error
        vim.notify(res.error, vim.log.levels.ERROR)
      end

      ctx.loading = res.scanning == true
      ctx.has_more = res.has_more == true
      ctx.total_items = res.total_items or 0
      ctx.last_revision = res.revision or 0
      ctx.last_query = q
      ctx.last_limit = limit

      local items = {}
      for i, it in ipairs(res.items or {}) do
        items[i] = convert_rust_item(it, ctx.git_root)
      end

      local out = {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_items or #items,
        scanning = ctx.loading,
        has_more = ctx.has_more,
      }

      if ctx.pending_restore_id then
        local found = false
        for _, it in ipairs(items) do
          if it.id == ctx.pending_restore_id then
            found = true
            break
          end
        end
        if found or not ctx.loading then
          out.restore_cursor_id = ctx.pending_restore_id
          out.restore_cursor_line = ctx.pending_restore_line
          out.force_preview = true
          ctx.pending_restore_id = nil
          ctx.pending_restore_line = nil
          ctx.pending_force_preview = false
        end
      elseif ctx.pending_force_preview and (#items > 0 or not ctx.loading) then
        out.force_preview = true
        ctx.pending_force_preview = false
      end

      ctx.last_response = out
      return out
    end,

    on_cursor_moved = function(lnum, total_rendered, ctx, query)
      ctx.pending_restore_id = nil
      ctx.pending_restore_line = nil
      if vim.trim(query or '') ~= '' then
        return
      end
      if total_rendered == 0 or lnum < total_rendered - SCROLL_PREFETCH_MARGIN then
        return
      end

      local total_loaded = ctx.total_items or 0
      local cur_limit = ctx.display_limit or DISPLAY_PAGE_SIZE
      if cur_limit < total_loaded then
        ctx.display_limit = math.min(total_loaded, cur_limit + DISPLAY_PAGE_SIZE)
        if ctx.refresh then
          ctx.refresh({ preserve_cursor = true, force_preview = false })
        end
      elseif ctx.has_more and not ctx.loading and ctx.session_id then
        local step = ctx.load_step or LOAD_MORE_STEP
        ctx.display_limit = total_loaded + DISPLAY_PAGE_SIZE
        local lm = backend.git_log_load_more(ctx.session_id, step)
        if lm and (lm.started or lm.queued) then
          ctx.loading = true
          if ctx.refresh then
            ctx.refresh({ preserve_cursor = true, force_preview = false })
          end
        end
      end
    end,

    on_close = function(ctx)
      if ctx.drilling_down then
        return
      end
      if ctx.session_id then
        backend.git_log_cancel(ctx.session_id, { only_if_scanning = true })
      end
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
        ctx.drilling_down = true
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
          local ordered = sort_targets_chronological_oldest_first(targets)
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
        ctx.drilling_down = true
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
          if ctx.session_id then
            backend.git_log_cancel(ctx.session_id, { only_if_scanning = true })
          end
          ctx.line_range = nil
          ctx.filter_file = not ctx.filter_file
          ctx.display_limit = DISPLAY_PAGE_SIZE
          ctx.explicit_limit = (ctx.opts and ctx.opts.limit) or nil
          ctx.last_revision = -1
          ctx.notified_error = nil
          ctx.keep_stale_on_reload = false
          ctx.pending_restore_id = nil
          ctx.pending_restore_line = nil
          ctx.pending_force_preview = true

          local opened, err = open_log_session(ctx, { force = false })
          if opened then
            ctx.session_id = opened.session_id
            ctx.branch = opened.branch
            ctx.prompt = build_log_prompt(ctx)
            ctx.loading = opened.scanning == true
            ctx.has_more = opened.has_more == true
          elseif err and err ~= '' then
            ctx.loading = false
            ctx.has_more = false
            vim.notify('git log failed: ' .. err, vim.log.levels.ERROR)
          end

          ctx.refresh({ preserve_cursor = false, force_preview = true })
          return 'keep_open'
        end,
      },

      load_more = {
        allow_empty = true,
        desc = 'Load more older commits',
        fn = function(_, ctx)
          if not ctx.git_root or not ctx.session_id then
            return 'keep_open'
          end
          local step = ctx.load_step or LOAD_MORE_STEP
          local res, err = backend.git_log_load_more(ctx.session_id, step)
          if not res then
            if err and err ~= '' then
              vim.notify('git log load_more failed: ' .. err, vim.log.levels.ERROR)
            end
            return 'keep_open'
          end
          if res.already_complete then
            vim.notify('All commits already loaded (' .. tostring(res.total_items or 0) .. ')', vim.log.levels.INFO)
            return 'keep_open'
          end
          if res.queued then
            vim.notify('Queued loading +' .. step .. ' older commits', vim.log.levels.INFO)
            return 'keep_open'
          end
          if res.started then
            ctx.loading = true
            ctx.display_limit = math.max(ctx.display_limit or DISPLAY_PAGE_SIZE, (res.total_items or 0) + DISPLAY_PAGE_SIZE)
            ctx.refresh({ preserve_cursor = true, force_preview = false })
          end
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
        local ordered = sort_targets_chronological_oldest_first(targets)
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
