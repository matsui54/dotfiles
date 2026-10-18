-- Tabline configuration (ported from autoload/tabline.vim)

local function my_tab_label(n)
  local buflist = vim.fn.tabpagebuflist(n)
  local winnr = vim.fn.tabpagewinnr(n)
  local bufname = vim.fn.bufname(buflist[winnr])
  local res = vim.fn.fnamemodify(bufname, ":t")
  if res == "" then
    res = "[]"
  end
  return res
end

local function get_tab_info(i, num_tab)
  local current_tab_nr = vim.fn.tabpagenr()
  local is_current = (i == current_tab_nr)

  local hi = is_current and "%#Normal#" or "%#TabLineFill#"
  local space1 = is_current and "  " or " "

  local bufnrs = vim.fn.tabpagebuflist(i)
  local bufno = #bufnrs >= 2 and tostring(#bufnrs) or ""

  local modified = false
  for _, b in ipairs(bufnrs) do
    if vim.fn.getbufvar(b, "&modified") == 1 then
      modified = true
      break
    end
  end
  local mod = modified and "+" or ""
  local space2 = (bufno .. mod) == "" and "" or " "

  local pre = space1 .. bufno .. mod .. space2
  local name = my_tab_label(i)
  local post = " "

  -- 現在のタブ以外で、前後のタブとの境界線 (|)
  if i ~= num_tab and i ~= current_tab_nr and i + 1 ~= current_tab_nr then
    post = post .. "|"
  elseif i + 1 == current_tab_nr then
    post = post .. " "
  end

  local len = vim.fn.strwidth(pre .. name .. post)
  return {
    hi = hi,
    pre = pre,
    name = name,
    post = post,
    len = len,
  }
end

function _G.my_tabline()
  local num_tab = vim.fn.tabpagenr("$")
  local screen_width = vim.o.columns
  local len_str = 0
  local tabs = {}

  for i = 1, num_tab do
    local info = get_tab_info(i, num_tab)
    tabs[i] = info
    len_str = len_str + info.len
  end

  -- 時刻とカレントディレクトリ
  local time = os.date("%H:%M")
  local dir = vim.fn.fnamemodify(vim.fn.getcwd(), ":~")
  if not dir:match("/$") then
    dir = dir .. "/"
  end
  local len_tail = vim.fn.strwidth(time .. dir) + 3

  -- 画面幅を超えている場合、カレントディレクトリを短縮
  if len_str + len_tail > screen_width then
    dir = vim.fn.substitute(dir, "\\/[^\\/]\\{3}\\zs[^\\/]\\+", "…", "g")
    len_tail = vim.fn.strwidth(time .. vim.fn.substitute(dir, "…", ".", "g")) + 3
  end

  -- それでも画面幅を超える場合、タブのファイル名を縮小
  if len_str + len_tail > screen_width then
    local capacity = screen_width - len_tail
    if capacity < len_str then
      local avr = math.floor(capacity / num_tab)
      for i = 1, num_tab do
        if tabs[i].len < avr then
          capacity = capacity + (avr - tabs[i].len)
        end
      end

      avr = math.floor(capacity / num_tab) - 1
      for i = 1, num_tab do
        if tabs[i].len > avr then
          local fixed_len = vim.fn.strwidth(tabs[i].pre .. tabs[i].post)
          local max_name_len = avr - fixed_len - 1
          if max_name_len > 0 then
            tabs[i].name = vim.fn.strcharpart(tabs[i].name, 0, max_name_len) .. "…"
          else
            tabs[i].name = "…"
          end
        end
      end
    end
  end

  local s = {}
  for i = 1, num_tab do
    local tab = tabs[i]
    table.insert(s, "%" .. i .. "T" .. tab.hi .. tab.pre .. tab.name .. tab.post .. "%T")
  end
  table.insert(s, "%=%#Normal#" .. time .. " " .. dir)
  return table.concat(s)
end

vim.opt.showtabline = 2
vim.opt.tabline = "%!v:lua.my_tabline()"
