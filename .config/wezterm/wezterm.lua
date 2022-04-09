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
			merge_tables(t1[k], t2[k])
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
	disable_default_key_bindings = true,
	keys = {
    { key = "c", mods = "CTRL|SHIFT", action = wezterm.action({ CopyTo = "Clipboard" }) },
    { key = "v", mods = "CTRL|SHIFT", action = wezterm.action({ PasteFrom = "Clipboard" }) },
    { key = "0", mods = "CTRL", action = "ResetFontSize" },
    { key = "=", mods = "CTRL", action = "IncreaseFontSize" },
    { key = "-", mods = "CTRL", action = "DecreaseFontSize" },
    { key = "t", mods = "CTRL|SHIFT", action = { SpawnTab = "CurrentPaneDomain" } },
    { key = "T", mods = "SUPER|SHIFT", action = wezterm.action({ SpawnTab="DefaultDomain" }) },
    { key = "w", mods = "CTRL|SHIFT", action = wezterm.action({ CloseCurrentPane = { confirm = true } }) },
    { key = "[", mods = "CTRL|SHIFT", action = wezterm.action({ ActivateTabRelative=-1 }) },
    { key = "Tab", mods = "CTRL|SHIFT", action = wezterm.action({ ActivateTabRelative=-1 }) },
    { key = "]", mods = "CTRL|SHIFT", action = wezterm.action({ ActivateTabRelative=1 }) },
    { key = "Tab", mods = "CTRL", action = wezterm.action({ ActivateTabRelative=1 }) },
    { key = "F11", action = "ToggleFullScreen" },
    -- { key = "K", mods = "CTRL|SHIFT", action = wezterm.action({ ClearScrollback="ScrollbackOnly" }) },
    { key = "q", mods = "CTRL|SHIFT", action = "QuickSelect" },
    { key = "F", mods = "CTRL|SHIFT", action = wezterm.action({ Search={CaseSensitiveString=""} }) },
    { key = "x", mods = "CTRL|SHIFT", action = "ActivateCopyMode" },
    { key = "PageUp", mods = "ALT", action = wezterm.action({ ScrollByPage = -1 }) },
    { key = "PageDown", mods = "ALT", action = wezterm.action({ ScrollByPage = 1 }) },
    { key = "r", mods = "CTRL|SHIFT", action = "ReloadConfiguration" },
    { key = "L", mods = "CTRL|SHIFT", action = "ShowDebugOverlay"  },
    { key = "e", mods = "ALT", action = wezterm.action({ SplitHorizontal = { domain = "CurrentPaneDomain" } }) },
    { key = "s", mods = "ALT", action = wezterm.action({ SplitVertical = { domain = "CurrentPaneDomain" } }) },
    { key = "h", mods = "ALT|SHIFT", action = wezterm.action({ ActivatePaneDirection = "Left" }) },
    { key = "l", mods = "ALT|SHIFT", action = wezterm.action({ ActivatePaneDirection = "Right" }) },
    { key = "k", mods = "ALT|SHIFT", action = wezterm.action({ ActivatePaneDirection = "Up" }) },
    { key = "j", mods = "ALT|SHIFT", action = wezterm.action({ ActivatePaneDirection = "Down" }) },
  },
}

return merge_tables(config, local_config)
