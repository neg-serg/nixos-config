-- LustyExplorer (sjbach/lusty) Lua port for modern Neovim.
--
-- Provides the LustyExplorer commands/filesystem/buffer explorers with the
-- original bottom-table + prompt UX, Mercury fuzzy matching and MRU ordering.
--
--   :LustyFilesystemExplorer [path]
--   :LustyFilesystemExplorerFromHere
--   :LustyBufferExplorer
--   :LustyBufferGrep
--
-- Mappings (unless g:LustyExplorerDefaultMappings == 0):
--   <Leader>lf  filesystem explorer (cwd)
--   <Leader>lr  filesystem explorer at the current file's directory
--   <Leader>lb  buffer explorer
--   <Leader>lg  buffer grep

local explorer = require('lusty.explorer')
local buffers = require('lusty.buffer_stack')
local fs = require('lusty.filesystem_explorer')
local be = require('lusty.buffer_explorer')
local bg = require('lusty.buffer_grep')

local M = {}

local function deprecated(old, new)
  vim.notify(':' .. old .. ' is deprecated; use :' .. new .. ' instead.', vim.log.levels.WARN)
end

function M.setup()
  explorer.ensure_highlights()
  buffers.register_autocmds()
  buffers.reset()

  vim.api.nvim_create_user_command('LustyFilesystemExplorer', function(o)
    fs.run(o.args == '' and nil or vim.fn.expand(o.args))
  end, { nargs = '?', desc = 'Lusty filesystem explorer' })

  vim.api.nvim_create_user_command('LustyFilesystemExplorerFromHere', function()
    local d = vim.fn.expand('%:p:h')
    fs.run(d == '' and vim.fn.getcwd() or d)
  end, { desc = 'Lusty filesystem explorer from current file dir' })

  vim.api.nvim_create_user_command('LustyBufferExplorer', function()
    be.run()
  end, { desc = 'Lusty buffer explorer' })

  vim.api.nvim_create_user_command('LustyBufferGrep', function()
    bg.run()
  end, { desc = 'Lusty buffer grep' })

  -- Deprecated non-prefixed aliases (they only warn, like the original).
  vim.api.nvim_create_user_command('BufferExplorer', function()
    deprecated('BufferExplorer', 'LustyBufferExplorer')
  end, {})
  vim.api.nvim_create_user_command('FilesystemExplorer', function()
    deprecated('FilesystemExplorer', 'LustyFilesystemExplorer')
  end, {})
  vim.api.nvim_create_user_command('FilesystemExplorerFromHere', function()
    deprecated('FilesystemExplorerFromHere', 'LustyFilesystemExplorerFromHere')
  end, {})

  -- Default mappings are ON unless the option explicitly disables them.
  local dm = vim.g.LustyExplorerDefaultMappings
  if not (dm == 0 or dm == false or dm == '0') then
    -- ,l must fire INSTANTLY: it is an exact map AND a prefix of the old
    -- ,l[fbgr] chords, so nvim would wait for a second key and swallow the
    -- first typed query letter (typing ',lgames' opened BufferGrep with
    -- 'ames').  Secondary functions moved off the 'l' prefix:
    --   ,l  filesystem explorer from here (nowait)
    --   ,C  filesystem explorer (cwd)
    --   ,B  buffer explorer
    --   ,G  buffer grep
    local function from_here()
      local d = vim.fn.expand('%:p:h')
      fs.run(d == '' and vim.fn.getcwd() or d)
    end
    vim.keymap.set('n', '<leader>l', from_here,
      { nowait = true, desc = 'Lusty filesystem explorer from here' })
    vim.keymap.set('n', '<leader>C', function()
      fs.run(nil)
    end, { desc = 'Lusty filesystem explorer (cwd)' })
    vim.keymap.set('n', '<leader>B', function()
      be.run()
    end, { desc = 'Lusty buffer explorer' })
    vim.keymap.set('n', '<leader>G', function()
      bg.run()
    end, { desc = 'Lusty buffer grep' })
  end
end

M.setup()

return M
