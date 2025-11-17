local wezterm = require 'wezterm'
local act = wezterm.action
-- Be safe when wezterm.gui is unavailable (e.g., headless contexts)
local gpus = (wezterm.gui and wezterm.gui.enumerate_gpus()) or {}

return {
  enable_wayland = true,
  prefer_egl = true,
  front_end = "WebGpu",
  -- Prefer second GPU if present (often discrete); fallback to first
  webgpu_preferred_adapter = gpus[2] or gpus[1],
  color_scheme = 'Catppuccin Macchiato',
  enable_tab_bar = false,
  enable_scroll_bar = true,
  inactive_pane_hsb = {
    saturation = 0.9,
    brightness = 0.7,
  },
  background = {
    {
      source = {
        Color="#24273a"
      },
      height = "100%",
      width = "100%",
    },
    {
      source = {
        File = os.getenv('HOME') .. '/.config/wezterm/lain.gif',
      },
      opacity = 0.02,
      vertical_align = "Middle",
      horizontal_align = "Center",
      height = "1824",
      width = "2724",
      repeat_y = "NoRepeat",
      repeat_x = "NoRepeat",
    },
  },
  -- Leader to replace SUPER-heavy combos (tmux-like)
  leader = { key = 'a', mods = 'CTRL', timeout_milliseconds = 1000 },
  launch_menu = {
    {
      args = { 'btop' },
    },
    {
      args = { 'cmatrix' },
    },
    {
      args = { 'pipes-rs' },
    },
  },
  keys = {
    {
      key = 'j',
      mods = 'CTRL|SHIFT',
      action = act.ScrollByPage(1)
    },
    {
      key = 'k',
      mods = 'CTRL|SHIFT',
      action = act.ScrollByPage(-1)
    },
    {
      key = 'g',
      mods = 'CTRL|SHIFT',
      action = act.ScrollToTop
    },
    {
      key = 'e',
      mods = 'CTRL|SHIFT',
      action = act.ScrollToBottom
    },
    -- Leader-based pane control
    { key = 'p', mods = 'LEADER', action = act.PaneSelect },
    { key = 'o', mods = 'LEADER', action = act.PaneSelect { mode = "SwapWithActive" } },
    { key = '%', mods = 'LEADER', action = act.SplitVertical { domain = 'CurrentPaneDomain' } },
    { key = '"', mods = 'LEADER', action = act.SplitHorizontal { domain = 'CurrentPaneDomain' } },

    -- Resize panes with leader + Shift + arrows (step 3)
    { key = 'LeftArrow',  mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Left', 3 } },
    { key = 'RightArrow', mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Right', 3 } },
    { key = 'UpArrow',    mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Up', 3 } },
    { key = 'DownArrow',  mods = 'LEADER|SHIFT', action = act.AdjustPaneSize { 'Down', 3 } },

    -- Navigate panes with leader + hjkl
    { key = 'h', mods = 'LEADER', action = act.ActivatePaneDirection 'Left' },
    { key = 'l', mods = 'LEADER', action = act.ActivatePaneDirection 'Right' },
    { key = 'k', mods = 'LEADER', action = act.ActivatePaneDirection 'Up' },
    { key = 'j', mods = 'LEADER', action = act.ActivatePaneDirection 'Down' },

    { key = 'z', mods = 'LEADER', action = act.TogglePaneZoomState },
    { key = 'q', mods = 'LEADER', action = act.CloseCurrentPane { confirm = true } },
    { key = 'b', mods = 'LEADER', action = act.RotatePanes 'CounterClockwise' },
    { key = 'n', mods = 'LEADER', action = act.RotatePanes 'Clockwise' },
    {
      key = 'd',
      mods = 'CTRL|SHIFT',
      action = act.ShowLauncher
    },
    {
      key = ':',
      mods = 'CTRL|SHIFT',
      action = act.ClearSelection
    },
    {
      key = 'Enter',
      mods = 'ALT',
      action = wezterm.action.DisableDefaultAssignment,
    },
  },
}
