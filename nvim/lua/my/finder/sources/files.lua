local backend = require('my.finder.backend')

local M = {}

local GIT_BADGES = {
  modified = { 'M ', 'MyFinderGitDirty' },
  staged_modified = { 'M ', 'MyFinderGitDirty' },
  untracked = { '? ', 'MyFinderGitNew' },
  staged_new = { 'A ', 'MyFinderGitNew' },
  deleted = { 'D ', 'Removed' },
  staged_deleted = { 'D ', 'Removed' },
  renamed = { 'R ', 'MyFinderGitDirty' },
}

local function normalize_dir(dir)
  local p = vim.fn.fnamemodify(dir or vim.fn.getcwd(), ':p')
  if #p > 1 and p:sub(-1) == '/' then
    p = p:sub(1, -2)
  end
  return p
end

---@param source_opts? table
---@return table
function M.new(source_opts)
  source_opts = source_opts or {}
  return {
    name = source_opts.name or 'files',
    title = source_opts.title or 'Files',
    prompt = '> ',
    show_preview = true,
    allow_preview = true,
    poll_scan = true,
    track_query = true,

    prepare = function(ctx, opts)
      local raw_dir = (opts and opts.dir) or source_opts.dir or vim.fn.getcwd()
      local target_dir = normalize_dir(raw_dir)
      local canon, err = backend.ensure_dir(target_dir)
      local dir = canon or target_dir

      local current_file = nil
      if ctx.origin_path and ctx.origin_path ~= '' then
        local norm_origin = vim.fs.normalize(ctx.origin_path)
        local norm_dir = vim.fs.normalize(dir)
        if norm_origin:sub(1, #norm_dir + 1) == norm_dir .. '/' then
          current_file = norm_origin:sub(#norm_dir + 2)
        end
      end

      return {
        dir = dir,
        current_file = current_file,
        dir_error = err,
      }
    end,

    search = function(query, ctx)
      if ctx.dir_error then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
        }
      end

      local res, err = backend.search_files(ctx.dir, query, {
        limit = 200,
        current_file = ctx.current_file,
      })
      if not res then
        return {
          items = {},
          total_matched = 0,
          total_items = 0,
          scanning = false,
          error = err,
        }
      end

      local items = {}
      local loc_lnum = res.loc_lnum
      local loc_col = res.loc_col

      for _, it in ipairs(res.items or {}) do
        local badge = GIT_BADGES[it.git_status]
        local prefix = badge and badge[1] or '  '
        local hl_list = nil
        if badge then
          hl_list = { { 0, 1, badge[2] } }
        end

        items[#items + 1] = {
          id = it.path,
          path = it.path,
          rel_path = it.rel_path,
          display = prefix .. it.rel_path,
          highlights = hl_list,
          match_indices = it.match_indices,
          match_offset = #prefix,
          lnum = loc_lnum,
          col = loc_col and math.max(0, loc_col - 1) or nil,
        }
      end

      return {
        items = items,
        total_matched = res.total_matched or #items,
        total_items = res.total_files or #items,
        scanning = res.scanning == true,
      }
    end,
  }
end

return M
