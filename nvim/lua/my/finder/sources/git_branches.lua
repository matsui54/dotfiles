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

---@param raw string
---@return table[], string[]
local function parse_branches(raw)
  local entries = {}
  local match_texts = {}
  for _, line in ipairs(vim.split(raw, '\n', { plain = true, trimempty = true })) do
    local head, name, hash, subject = line:match('^([^\t]*)\t([^\t]+)\t([^\t]*)\t(.*)$')
    if name and not name:match('/HEAD$') then
      local is_cur = head == '*'
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
        id = 'branch:' .. name,
        branch = name,
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

function M.new()
  return {
    name = 'git_branches',
    title = 'Git Branches',
    prompt = 'branch> ',
    show_preview = true,
    allow_preview = true,

    prepare = function(ctx)
      local root = find_git_root(ctx.origin_path)
      return {
        git_root = root,
        entries = nil,
        match_texts = nil,
        loading = root ~= nil,
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

      vim.system({
        'git',
        '-C',
        ctx.git_root,
        'for-each-ref',
        '--sort=-committerdate',
        '--format=%(HEAD)%09%(refname:short)%09%(objectname:short)%09%(subject)',
        'refs/heads',
        'refs/remotes',
      }, { text = true }, function(res)
        vim.schedule(function()
          if res.code == 0 and res.stdout then
            ctx.entries, ctx.match_texts = parse_branches(res.stdout)
          else
            ctx.entries, ctx.match_texts = {}, {}
          end
          ctx.loading = false
          async_cb(build_response())
        end)
      end)

      return {
        items = {},
        total_matched = 0,
        total_items = 0,
        scanning = true,
      }
    end,

    preview = function(item, pctx, cb)
      if not item.git_root or not item.branch then
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
        item.branch,
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

    on_select = function(targets)
      local it = targets[1]
      if not it or not it.git_root or not it.branch then
        return
      end
      local branch = it.branch
      local args = { 'git', '-C', it.git_root, 'checkout', branch }
      if branch:match('^origin/') then
        local local_name = branch:gsub('^origin/', '')
        args = { 'git', '-C', it.git_root, 'checkout', '-t', branch }
        -- If local branch already exists, just switch to it
        local check = vim.system({ 'git', '-C', it.git_root, 'show-ref', '--verify', 'refs/heads/' .. local_name }, { text = true }):wait()
        if check.code == 0 then
          args = { 'git', '-C', it.git_root, 'checkout', local_name }
        end
      end

      vim.system(args, { text = true }, function(res)
        vim.schedule(function()
          if res.code == 0 then
            vim.notify('Switched to branch: ' .. branch, vim.log.levels.INFO)
            pcall(vim.cmd, 'checktime')
          else
            vim.notify('git checkout failed: ' .. (res.stderr or ''), vim.log.levels.ERROR)
          end
        end)
      end)
    end,
  }
end

return M
