-- Native buffer explorer: the Lusty buffer explorer (MRU order, current
-- buffer last, modified [+] marker, extension colours) rendered in the
-- native bottom float instead of the Lua table UI. C-d unloads the selected
-- buffer, Enter/Tab switch to it, C-t/C-o/C-v open it in a tab/split/vsplit.
-- C-Space marks buffers (multi-select): C-d then unloads the whole marked set.

local buffers = require('lusty.buffer_stack')
local lsc = require('lusty.ls_colors')
local source = require('lusty.native_source')

local function open_buffer(bufnr, mode)
  local cmd = mode == 'enter' and 'b ' or mode == 'tab' and 'tab split | b ' or mode == 'split' and 'sp | b ' or 'vs | b '
  vim.cmd('silent ' .. cmd .. bufnr)
end

-- Item snapshot in MRU order; the current buffer is rotated to the end by
-- buffer_stack and gets the Constant highlight.
local function snapshot_items()
  local curbuf = vim.fn.bufnr('%')
  local out = {}
  for _, entry in ipairs(buffers.compute_buffer_entries()) do
    local label = entry.short_name
    if entry.modified then
      label = label .. ' [+]'
    end
    local item = {
      bufnr = entry.bufnr,
      name = entry.name,
      short_name = entry.short_name,
      label = label,
    }
    if entry.bufnr == curbuf then
      item.current = true
    else
      local group = lsc.group_for({ name = entry.name ~= '' and entry.name or entry.short_name, is_dir = false })
      if group then
        item.group = group
      end
    end
    out[#out + 1] = item
  end
  return out
end

-- The run guard, the query memory, the first-letter filter and the running
-- flag around on_open/on_delete/on_close are shared with the other source
-- pickers (lusty.native_source).
local M = source.define({
  title = 'Buffers',
  multi = true,
  snapshot = snapshot_items,
  filter_key = 'short_name',
  filter_tie = 'bufnr',
  on_open = function(item, mode)
    open_buffer(item.bufnr, mode)
  end,
  on_delete = function(item)
    if vim.fn.bufexists(item.bufnr) == 1 then
      vim.cmd('silent bdelete! ' .. item.bufnr)
    end
  end,
})

return M
