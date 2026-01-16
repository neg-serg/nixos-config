-- Minimal config for kitty-scrollback.nvim Neovim overlay
-- Scope: used only when launched via kitty kitten with -u this file

-- Optional light tweaks
vim.g.mapleader = ' '
vim.opt.termguicolors = true
vim.opt.number = false
vim.opt.relativenumber = false

-- Defer plugin setup until kitty-scrollback adds itself to runtimepath
-- The kitten injects a VimEnter callback that appends the plugin path
-- and then triggers the User event "KittyScrollbackLaunch".
-- Ensure our colorscheme is available in this minimal runtime
pcall(function()
  local neg_path = vim.fn.stdpath('data') .. '/lazy/neg.nvim'
  if vim.uv or vim.loop then -- nvim 0.10+ or legacy
    local fs = (vim.uv or vim.loop)
    if fs.fs_stat(neg_path) then
      vim.opt.runtimepath:append(neg_path)
    end
  end
  pcall(vim.cmd.colorscheme, 'neg')
end)

-- Yank helpers: copy selection to system clipboard and optionally close overlay
local function _ksb_should_quit_after_yank()
  if vim.g.kitty_scrollback_quit_after_yank ~= nil then
    return not (vim.g.kitty_scrollback_quit_after_yank == false or vim.g.kitty_scrollback_quit_after_yank == 0)
  end
  local v = vim.env.KITTY_SCROLLBACK_QUIT_AFTER_YANK
  if v ~= nil then
    v = tostring(v):lower()
    return not (v == '0' or v == 'false' or v == 'no')
  end
  return true -- default: enabled
end

local function _ksb_yank_and_maybe_quit()
  local keys = vim.api.nvim_replace_termcodes('"+y', true, false, true)
  vim.api.nvim_feedkeys(keys, 'x', false)
  if _ksb_should_quit_after_yank() then
    local ok, api = pcall(require, 'kitty-scrollback.api')
    if ok then
      api.quit_all()
    else
      pcall(vim.cmd, 'qa!')
    end
  end
end

-- Direct clipboard yank on Shift+Y and Enter without any UI
vim.keymap.set('v', 'Y', _ksb_yank_and_maybe_quit, { noremap = true, silent = true })
vim.keymap.set('v', '<CR>', _ksb_yank_and_maybe_quit, { noremap = true, silent = true })

vim.api.nvim_create_autocmd('User', {
  pattern = 'KittyScrollbackLaunch',
  once = true,
  callback = function()
    -- Configure kitty-scrollback before it launches
    local ok, ksb = pcall(require, 'kitty-scrollback')
    if ok then
      ksb.setup({
        -- Global defaults applied to all configs
        {
          status_window = { show_timer = true },
          kitty_get_text = {
            ansi = true,
            clear_selection = true,
          },
          paste_window = {
            -- avoid any paste-window yank interference
            yank_register_enabled = false,
            hide_footer = true,
          },
        },
        -- Override builtin to prefer only the screen (lighter, fewer issues)
        ksb_builtin_get_text_all = {
          kitty_get_text = { extent = 'screen' },
        },
      })
    end
  end,
})
