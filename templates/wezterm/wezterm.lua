-- WezTerm config written by devenv. Put your own tweaks in local.lua next to this
-- file: it gets the config table and can change anything (see the end).
local wezterm = require("wezterm")
local act = wezterm.action
local config = wezterm.config_builder()

-- @@DEVENV_SETTINGS@@

-- Look: same Tokyo Night palette as tmux and Neovim. JetBrains Mono and the
-- Nerd Font symbols ship inside WezTerm, so no font install is needed.
config.color_scheme = "Tokyo Night"
config.font = wezterm.font_with_fallback({ "JetBrains Mono", "Symbols Nerd Font Mono" })
config.font_size = devenv.font_size
config.line_height = 1.1
config.window_padding = { left = 6, right = 6, top = 4, bottom = 2 }
config.window_decorations = "RESIZE"
config.hide_tab_bar_if_only_one_tab = true -- tmux is the tab bar
config.use_fancy_tab_bar = false
config.scrollback_lines = 20000
config.audible_bell = "Disabled"
config.adjust_window_size_when_changing_font_size = false
config.initial_cols = 160
config.initial_rows = 45

-- Let Option/Alt act as Meta so tmux's Alt-1..9 and Neovim's Alt maps work.
config.send_composed_key_when_left_alt_is_pressed = false
config.send_composed_key_when_right_alt_is_pressed = true

-- Every window opens straight into tmux (session "main", re-attached if it exists).
local into_tmux = "command -v tmux >/dev/null 2>&1 && exec tmux new-session -A -s main || exec " .. devenv.shell .. " -l"

if devenv.wsl_distro then
  -- Windows: WezTerm runs natively, the shell, tmux and Neovim run in WSL.
  config.wsl_domains = {
    {
      name = "WSL:" .. devenv.wsl_distro,
      distribution = devenv.wsl_distro,
      default_cwd = "~",
      default_prog = { devenv.shell, "-l", "-i", "-c", into_tmux },
    },
  }
  config.default_domain = "WSL:" .. devenv.wsl_distro
else
  config.default_prog = { devenv.shell, "-l", "-i", "-c", into_tmux }
end

local plain_shell = act.SpawnCommandInNewTab({ args = { devenv.shell, "-l" } })

config.keys = {
  -- A plain shell tab without tmux, for the rare time you want one.
  { key = "T", mods = "CTRL|SHIFT", action = plain_shell },
  -- Ctrl-Shift-F toggles full screen.
  { key = "F", mods = "CTRL|SHIFT", action = act.ToggleFullScreen },
}

if wezterm.target_triple:find("darwin") then
  -- Cmd shortcuts drive tmux (prefix is Ctrl-a = \x01).
  local function tmux(keys)
    return act.SendString("\x01" .. keys)
  end
  table.insert(config.keys, { key = "t", mods = "CMD", action = tmux("c") })
  table.insert(config.keys, { key = "d", mods = "CMD", action = tmux("|") })
  table.insert(config.keys, { key = "d", mods = "CMD|SHIFT", action = tmux("-") })
  table.insert(config.keys, { key = "k", mods = "CMD", action = tmux("f") })
  table.insert(config.keys, { key = "g", mods = "CMD", action = tmux("g") })
  for i = 1, 9 do
    table.insert(config.keys, { key = tostring(i), mods = "CMD", action = tmux(tostring(i)) })
  end
  table.insert(config.keys, { key = "T", mods = "CMD|SHIFT", action = plain_shell })
end

-- Your overrides: ~/.config/wezterm/local.lua returning function(config) ... end
local ok, user = pcall(require, "local")
if ok and type(user) == "function" then
  user(config)
end

return config
