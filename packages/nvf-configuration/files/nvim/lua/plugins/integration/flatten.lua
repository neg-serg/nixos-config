-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ willothy/flatten.nvim                                                        │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'willothy/flatten.nvim',
  lazy = false,
  priority = 1001,
  opts = function()
    local env = vim.env or {}
    local function present(val) return val ~= nil and val ~= '' end
    local is_kitty = (env.TERM == 'xterm-kitty') or present(env.KITTY_WINDOW_ID) or present(env.KITTY_LISTEN_ON)
    local is_wezterm = (env.TERM_PROGRAM == 'WezTerm') or present(env.WEZTERM_PANE)

    return {
      block_for = {
        gitcommit = true,
        gitrebase = true,
        NeogitCommitMessage = true,
      },
      integrations = {
        kitty = is_kitty,
        wezterm = is_wezterm,
      },
    }
  end,
  config = function(_, opts)
    local ok, flatten = pcall(require, 'flatten'); if not ok then return end
    flatten.setup(opts)
  end,
}
