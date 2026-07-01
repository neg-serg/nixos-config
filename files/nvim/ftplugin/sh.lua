-- gf for shell scripts: follow source/. directives to their target file.
-- Handles: source ./lib.sh, . ../common, source $ZDOTDIR/aliases, etc.

local nav = require('utils.nav')

local function source_target()
  local line = vim.api.nvim_get_current_line()
  -- Match 'source <path>' or '. <path>' with optional quoting and leading whitespace.
  -- Stop at whitespace, semicolon, or quotes to avoid capturing trailing tokens.
  local path = line:match("^%s*source%s+[\"']?([^\"'%s;]+)[\"']?")
            or line:match("^%s*%.%s+[\"']?([^\"'%s;]+)[\"']?")
  if not path then return nil end
  -- Expand shell variables Neovim's environment knows about ($HOME, $ZDOTDIR, etc.)
  path = path:gsub('%$(%w+)',      function(v) return vim.env[v] or ('$' .. v) end)
  path = path:gsub('%${(%w+)}',   function(v) return vim.env[v] or ('${' .. v .. '}') end)
  return path
end

local function follow_source()
  local path = source_target()
  if not path then return vim.cmd('normal! gf') end
  local resolved = nav.resolve_path(path, { extensions = { '.sh', '.zsh', '.bash' } })
  if resolved then nav.open_file(resolved) end
end

vim.keymap.set('n', 'gf', follow_source, { buffer = true, desc = 'Follow source/. path' })
vim.keymap.set('n', '<CR>', follow_source, { buffer = true, desc = 'Follow source/. path' })
