-- MRU buffer stack (port of lusty/src/lusty/buffer-stack.rb).

local util = require('lusty.util')

local M = {}

-- Ordered oldest .. newest.
local stack = {}
local registered = false

local function cull()
  local out = {}
  for _, b in ipairs(stack) do
    if vim.fn.bufexists(b) == 1 and vim.fn.getbufvar(b, '&buflisted') == 1 then
      out[#out + 1] = b
    end
  end
  stack = out
end

function M.reset()
  stack = {}
  local infos = vim.fn.getbufinfo({ buflisted = 1 })
  for _, info in ipairs(infos) do
    stack[#stack + 1] = info.bufnr
  end
end

function M.push(bufnr)
  if type(bufnr) ~= 'number' then
    return
  end
  -- remove existing occurrence, then append (move to most-recent)
  for i = #stack, 1, -1 do
    if stack[i] == bufnr then
      table.remove(stack, i)
    end
  end
  stack[#stack + 1] = bufnr
end

function M.pop(bufnr)
  for i = #stack, 1, -1 do
    if stack[i] == bufnr then
      table.remove(stack, i)
    end
  end
end

-- Most-recent-first list of listed buffer numbers.
function M.numbers()
  cull()
  local out = {}
  for i = #stack, 1, -1 do
    out[#out + 1] = stack[i]
  end
  return out
end

function M.register_autocmds()
  if registered then
    return
  end
  registered = true
  local group = vim.api.nvim_create_augroup('LustyExplorerPortBufStack', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufAdd', 'BufEnter' }, {
    group = group,
    callback = function()
      M.push(tonumber(vim.fn.expand('<abuf>')))
    end,
  })
  vim.api.nvim_create_autocmd({ 'BufDelete', 'BufWipeout' }, {
    group = group,
    callback = function()
      M.pop(tonumber(vim.fn.expand('<abuf>')))
    end,
  })
end

-- Entry list for BufferExplorer/BufferGrep, mirroring
-- Entry::compute_buffer_entries(): MRU order with the most recent entry
-- (normally the current buffer) rotated to the end of the list.
function M.compute_buffer_entries()
  local entries = {}
  for _, n in ipairs(M.numbers()) do
    if vim.fn.bufexists(n) == 1 and vim.fn.getbufvar(n, '&buflisted') == 1 then
      entries[#entries + 1] = {
        bufnr = n,
        name = vim.fn.bufname(n),
      }
    end
  end
  if #entries > 1 then
    table.insert(entries, table.remove(entries, 1))
  end

  -- Shorten names: keep only as much path as needed to disambiguate
  -- buffers that share a basename (BufferStack#shorten_paths).
  local by_base = {}
  for _, e in ipairs(entries) do
    local base = e.name ~= '' and util.basename(e.name) or nil
    if base then
      by_base[base] = by_base[base] or {}
      by_base[base][#by_base[base] + 1] = e
    end
  end
  local prefix_for = {}
  for base, list in pairs(by_base) do
    if #list > 1 then
      local names = {}
      local has_relative = false
      for _, e in ipairs(list) do
        names[#names + 1] = e.name
        if not e.name:find('/', 1, true) then
          has_relative = true
        end
      end
      if not has_relative then
        prefix_for[base] = util.longest_common_prefix(names)
      end
    end
  end
  for _, e in ipairs(entries) do
    if e.name == '' then
      e.short_name = '[No Name]'
    elseif e.name:sub(1, 6) == 'scp://' then
      e.short_name = e.name
    else
      local base = util.basename(e.name)
      local pref = prefix_for[base]
      if pref and pref ~= '' then
        e.short_name = e.name:sub(#pref + 1)
      else
        e.short_name = base
      end
    end
    e.modified = vim.fn.getbufvar(e.bufnr, '&modified') == 1
  end
  return entries
end

return M

