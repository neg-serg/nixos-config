-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ wallpants/ghost-text.nvim — edit browser textareas in real Neovim              │
-- └───────────────────────────────────────────────────────────────────────────────────┘
-- GhostText protocol client: click the GhostText extension icon on any textarea and the
-- content opens in this Neovim instance; edits sync bidirectionally (port 4001).
-- Requires the bun binary (added via programs.neovim.extraPackages in neovim.nix).
return {
  "wallpants/ghost-text.nvim",
  -- Not lazy: the GhostText server must autostart (default) whenever nvim runs.
  lazy = false,
  opts = {},
}
