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
local native = require('lusty.native')
local be = require('lusty.buffer_explorer')
local bg = require('lusty.buffer_grep')

-- Native picker is the default; g:LustyExplorerNative = 0 keeps the Lua port
-- (the fallback). Buffer explorer/grep have no native mode yet, so those
-- always use the Lua port.
local function native_enabled()
  local n = vim.g.LustyExplorerNative
  return not (n == 0 or n == false or n == '0')
end

local function run_fs(dir)
  if native_enabled() then
    native.run(dir == nil and vim.fn.getcwd() or dir)
  else
    fs.run(dir)
  end
end

local M = {}

local function deprecated(old, new)
  vim.notify(':' .. old .. ' is deprecated; use :' .. new .. ' instead.', vim.log.levels.WARN)
end

function M.setup()
  explorer.ensure_highlights()
  buffers.register_autocmds()
  buffers.reset()

  vim.api.nvim_create_user_command('LustyFilesystemExplorer', function(o)
    run_fs(o.args == '' and nil or vim.fn.expand(o.args))
  end, { nargs = '?', desc = 'Lusty filesystem explorer (native unless g:LustyExplorerNative=0)' })

  vim.api.nvim_create_user_command('LustyFilesystemExplorerFromHere', function()
    local d = vim.fn.expand('%:p:h')
    run_fs(d == '' and vim.fn.getcwd() or d)
  end, { desc = 'Lusty filesystem explorer from current file dir (native unless g:LustyExplorerNative=0)' })

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
      run_fs(d == '' and vim.fn.getcwd() or d)
    end
    vim.keymap.set('n', '<leader>l', from_here,
      { nowait = true, desc = 'Lusty filesystem explorer from here (native)' })
    vim.keymap.set('n', '<leader>C', function()
      run_fs(nil)
    end, { desc = 'Lusty filesystem explorer (cwd, native)' })
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
