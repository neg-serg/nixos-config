-- Native buffer explorer: the Lusty buffer explorer (MRU order, current
-- buffer last, modified [+] marker, extension colours) rendered in the
-- native bottom float instead of the Lua table UI. C-d unloads the selected
-- buffer, Enter/Tab switch to it, C-t/C-o/C-v open it in a tab/split/vsplit.
-- C-Space marks buffers (multi-select): C-d then unloads the whole marked set.

local buffers = require('lusty.buffer_stack')
local pick = require('lusty.native_pick')
local fuzzy = require('lusty.fuzzy')
local mercury = require('lusty.mercury')
local util = require('lusty.util')
local lsc = require('lusty.ls_colors')

local M = {}

-- Lua port parity: remember the last filter between runs.
local previous_input = ''

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

-- Filtering mirrors the Lua buffer explorer: the first query letter must
-- prefix the buffer basename, then entries are scored (mercury or the
-- fuzzy engine) on the short name, ties broken by buffer number.
local function make_source(holder)
  return function(query)
    if query == '' then
      return holder.items
    end
    local use_mercury = tostring(vim.g.LustyExplorerFuzzyEngine or '') == 'mercury'
    local first = query:sub(1, 1):lower()
    local scored = {}
    for _, it in ipairs(holder.items) do
      local base_first = (util.basename(it.short_name) or ''):sub(1, 1):lower()
      if base_first == first then
        local score = use_mercury and mercury.score(it.short_name, query) or fuzzy.score(it.short_name, query)
        if score and score ~= 0.0 then
          scored[#scored + 1] = { it = it, score = score }
        end
      end
    end
    table.sort(scored, function(a, b)
      if a.score == b.score then
        return a.it.bufnr < b.it.bufnr
      end
      return a.score > b.score
    end)
    local res = {}
    for _, s in ipairs(scored) do
      res[#res + 1] = s.it
    end
    return res
  end
end

local running = false

function M.run()
  if running then
    return
  end
  running = true
  local holder = { items = snapshot_items() }
  local function on_delete(item)
    if vim.fn.bufexists(item.bufnr) == 1 then
      vim.cmd('silent bdelete! ' .. item.bufnr)
    end
    -- rebuild the item list; the source reads holder.items, so the picker
    -- sees the fresh list on its next refresh
    holder.items = snapshot_items()
  end
  pick.pick({
    title = 'Buffers',
    query = previous_input,
    multi = true,
    source = make_source(holder),
    on_open = function(item, mode)
      running = false
      open_buffer(item.bufnr, mode)
    end,
    on_delete = on_delete,
    on_close = function(p2)
      running = false
      if p2 and p2.query then
        previous_input = p2.query
      end
    end,
  })
end

function M.is_running()
  return running
end

return M
