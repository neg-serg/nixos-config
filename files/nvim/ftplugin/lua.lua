-- gf for Lua files: resolve require('module.name') to its source file.
-- Searches runtimepath lua/ directories (covers both config modules and plugins),
-- then falls back to fzf-lua if nothing found.

local nav = require('utils.nav')
local uv  = vim.uv

local function require_module_at_cursor()
  local line = vim.api.nvim_get_current_line()
  -- Match: require('foo.bar'), require("foo.bar"), require  ('foo.bar'), etc.
  local mod = line:match([[require%s*%(?%s*['"]([^'"]+)['"]%s*%)?]])
  if not mod then return nil end
  -- Convert dot-notation to path: 'utils.nav' → 'utils/nav'
  return mod:gsub('%.', '/')
end

local function follow_require()
  local mod_path = require_module_at_cursor()
  if not mod_path then return vim.cmd('normal! gf') end

  -- Search runtimepath lua/ entries — same list Neovim uses when loading modules.
  -- Check both module.lua and module/init.lua (the two canonical Lua module forms).
  for _, rtp in ipairs(vim.api.nvim_list_runtime_paths()) do
    for _, suffix in ipairs({
      '/lua/' .. mod_path .. '.lua',
      '/lua/' .. mod_path .. '/init.lua',
    }) do
      local full = rtp .. suffix
      if uv.fs_stat(full) then
        nav.open_file(full)
        return
      end
    end
  end

  -- fzf fallback: use the last path component as the search query.
  local tail = mod_path:match('[^/]+$') or mod_path
  local ok, fzf = pcall(require, 'fzf-lua')
  if ok then fzf.files({ query = tail, cwd = nav.project_root() }) end
end

vim.keymap.set('n', 'gf', follow_require, { buffer = true, desc = "Follow require() to source" })
vim.keymap.set('n', '<CR>', follow_require, { buffer = true, desc = "Follow require() to source" })
