-- Lusty pickers for the files/nvim config (native Rust backend).
--
--   :LustyFilesystemExplorer [path]   filesystem float (cwd or the given path)
--   :LustyFilesystemExplorerFromHere  filesystem float from the current file's dir
--   :LustyBufferExplorer              MRU buffer float
--   :LustyBufferGrep                  Ruby-ish regex over the loaded buffers
--   :LustyRecent                      recent files / visited dirs
--
-- Mappings (unless g:LustyExplorerDefaultMappings == 0):
--   <Leader>l   filesystem explorer from the current file's directory
--   <Leader>C   filesystem explorer (cwd)
--   <C-b>       buffer explorer
--   <C-g>       buffer grep
--   <Leader>.   recent files
--
-- The pickers are rendered by the Rust backend (`lusty serve`, see native.lua);
-- the historical Lua port was removed, so there is no fallback mode any more.

local buffers = require('lusty.buffer_stack')
local native = require('lusty.native')
local nbufs = require('lusty.native_buffers')
local ngrep = require('lusty.native_buffer_grep')
local nrecent = require('lusty.native_recent')

local M = {}

local function deprecated(old, new)
  vim.notify(':' .. old .. ' is deprecated; use :' .. new .. ' instead.', vim.log.levels.WARN)
end

local function run_fs(dir)
  native.run(dir == nil and vim.fn.getcwd() or dir)
end

function M.setup()
  -- g:LustyExplorerNative = 0 used to select the Lua port; it is gone now.
  local n = vim.g.LustyExplorerNative
  if n == 0 or n == false or n == '0' then
    vim.notify('lusty: the Lua port was removed; using the native picker', vim.log.levels.WARN)
  end

  buffers.register_autocmds()
  buffers.reset()

  vim.api.nvim_create_user_command('LustyFilesystemExplorer', function(o)
    run_fs(o.args == '' and nil or vim.fn.expand(o.args))
  end, { nargs = '?', desc = 'Lusty filesystem explorer' })

  vim.api.nvim_create_user_command('LustyFilesystemExplorerFromHere', function()
    local d = vim.fn.expand('%:p:h')
    run_fs(d == '' and vim.fn.getcwd() or d)
  end, { desc = 'Lusty filesystem explorer from the current file dir' })

  vim.api.nvim_create_user_command('LustyBufferExplorer', function()
    nbufs.run()
  end, { desc = 'Lusty buffer explorer' })

  vim.api.nvim_create_user_command('LustyBufferGrep', function()
    ngrep.run()
  end, { desc = 'Lusty buffer grep' })

  vim.api.nvim_create_user_command('LustyRecent', function()
    nrecent.run()
  end, { desc = 'Lusty recent files' })

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
    -- ,l fires INSTANTLY (nowait): it used to be a prefix of the ,l[fbgr]
    -- chords, so nvim waited for a second key and swallowed the first typed
    -- query letter (',lgames' opened BufferGrep with 'ames'). The secondary
    -- functions live on ,C / C-b / C-g / ,. instead.
    local function from_here()
      local d = vim.fn.expand('%:p:h')
      run_fs(d == '' and vim.fn.getcwd() or d)
    end
    vim.keymap.set('n', '<leader>l', from_here,
      { nowait = true, desc = 'Lusty filesystem explorer from here' })
    vim.keymap.set('n', '<leader>C', function()
      run_fs(nil)
    end, { desc = 'Lusty filesystem explorer (cwd)' })
    vim.keymap.set('n', '<leader>.', function()
      nrecent.run()
    end, { nowait = true, desc = 'Lusty recent files' })
    -- C-b / C-g override the stock normal-mode maps (quickfix list / word
    -- count); lusty loads after 02-bindings, so the set happens later.
    -- nowait: with <C-b>q/<C-b>d chords present nvim would wait for a
    -- timeoutlen before firing the plain map.
    vim.keymap.set('n', '<C-b>', function()
      nbufs.run()
    end, { nowait = true, desc = 'Lusty buffer explorer' })
    vim.keymap.set('n', '<C-g>', function()
      ngrep.run()
    end, { nowait = true, desc = 'Lusty buffer grep' })
  end
end

M.setup()

return M
