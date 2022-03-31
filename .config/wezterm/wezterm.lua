local wezterm = require 'wezterm';
return {
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
