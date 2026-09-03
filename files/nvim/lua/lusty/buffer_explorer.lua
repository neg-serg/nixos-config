-- BufferExplorer: port of lusty/src/lusty/buffer-explorer.rb.

local mercury = require('lusty.mercury')
local buffers = require('lusty.buffer_stack')
local ls_colors = require('lusty.ls_colors')
local E = require('lusty.explorer')

local M = {}

local e = E.Explorer.new({
  title = 'LustyExplorer--Buffers',
})

-- Color buffers by their file extension (dircolors rules).
e.color_entry = function(entry)
  return ls_colors.group_for({
    name = entry.name or entry.short_name,
    is_dir = false,
  })
end


-- Prepare the entry list for a fresh run.  The buffer MRU order comes from
-- buffer_stack.compute_buffer_entries() (most recent first, current rotated
-- to the end); the current buffer gets a dedicated highlight.
local function fresh_entries()
  local curbuf = vim.fn.bufnr('%')
  local entries = buffers.compute_buffer_entries()
  for _, entry in ipairs(entries) do
    entry.is_current = entry.bufnr == curbuf
    if entry.modified then
      entry.label = entry.short_name .. ' [+]'
    else
      entry.label = entry.short_name
    end
  end
  return entries
end

local function run_explorer()
  e.prompt:clear()
  e.entries = fresh_entries()
  e.selected = 0
  e:start()
end

e.compute_sorted_matches = function(self)
  local abbrev = self.prompt.input
  if abbrev == '' then
    -- MRU order (as prepared).
    return self.entries
  end

  local matches = {}
  for _, entry in ipairs(self.entries) do
    entry.score = mercury.score(entry.short_name, abbrev)
    if entry.score ~= 0.0 then
      matches[#matches + 1] = entry
    end
  end
  table.sort(matches, function(a, b)
    if a.score == b.score then
      return a.bufnr < b.bufnr
    end
    return a.score > b.score
  end)
  return matches
end

local function open_buffer(number, mode)
  if mode == 'current_tab' then
    vim.cmd('silent b ' .. number)
  elseif mode == 'new_tab' then
    vim.cmd('silent tab split | b ' .. number)
  elseif mode == 'new_split' then
    vim.cmd('silent sp | b ' .. number)
  elseif mode == 'new_vsplit' then
    vim.cmd('silent vs | b ' .. number)
  end
end

e.open_entry = function(self, entry, mode)
  self:cleanup()
  pcall(open_buffer, entry.bufnr, mode)
end

-- <C-d>: unload the selected buffer, then reopen the explorer.
local function unload_selected()
  local entry = e.matches[e.selected + 1]
  if not entry then
    return
  end
  local prev = e.selected
  e:cleanup()
  if vim.fn.bufexists(entry.bufnr) == 1 then
    pcall(vim.cmd, 'silent bdelete! ' .. entry.bufnr)
  end
  run_explorer()
  -- Restore the previous selection position.
  if prev >= #e.matches then
    e.selected = math.max(0, prev - 1)
  else
    e.selected = prev
  end
end

e.key_pressed = function(self, code)
  if code == 4 then
    unload_selected()
    return
  end
  E.Explorer.key_pressed(self, code)
end

function M.run()
  if e.running then
    return
  end
  run_explorer()
end

function M.explorer()
  return e
end

return M
