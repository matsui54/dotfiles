local wezterm = require 'wezterm';

local function load_local_config()
	local ok, _ = pcall(require, "local")
	if not ok then
		return {}
	end
	return require("local").setup()
end
local local_config = load_local_config()

local function merge_tables(t1, t2)
	for k, v in pairs(t2) do
		if (type(v) == "table") and (type(t1[k] or false) == "table") then
			M.merge_tables(t1[k], t2[k])
		else
			t1[k] = v
		end
	end
	return t1
end

local config = {
  font = wezterm.font("Cica"),
  font_size = 14.0,
  color_scheme = "Terminal Basic",
  use_ime = true,
  window_decorations = "RESIZE",
  window_padding = {
    left = 4,
    right = 4,
    top = 0,
    bottom = 0,
  },
}

return merge_tables(config, local_config)
