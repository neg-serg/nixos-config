-- Native buffer grep: the Lusty buffer grep (Ruby-ish case-insensitive regex
-- over the open listed buffers) rendered in the native bottom float.
-- An empty pattern lists the buffers themselves; typing greps them live.
-- Enter/Tab switch to the buffer, C-t/C-o/C-v open in tab/split/vsplit and
-- jump to the matched line (like the Lua port).

local buffers = require('lusty.buffer_stack')
local pick = require('lusty.native_pick')
local explorer = require('lusty.explorer')
-- Regex translation is shared with the Lua port implementation.
local lua_grep = require('lusty.buffer_grep')

local M = {}

-- Lua port parity: remember the last pattern between runs.
local previous_input = ''
local running = false

local function compile_pattern(input)
  local ok, vpat = pcall(lua_grep.translate_regex, input)
  if not ok then
    return nil
  end
  local ok2 = pcall(vim.regex, vpat)
  if not ok2 then
    return nil
  end
  return vpat
end

local function open_grep_entry(item, mode)
  local cmd = mode == 'enter' and 'b ' or mode == 'tab' and 'tab split | b ' or mode == 'split' and 'sp | b ' or 'vs | b '
  vim.cmd('silent ' .. cmd .. item.bufnr)
  if item.line then
    vim.cmd(tostring(item.line))
  end
end

-- Grep the snapshot buffers for `query`; byte-accurate sub-highlights like
-- the Lua port (filename / line number / context / match).
local function make_source(snap)
  return function(query)
    if query == '' then
      -- No query: list all buffers, like the original.
      local out = {}
      for _, entry in ipairs(snap) do
        out[#out + 1] = { bufnr = entry.bufnr, label = entry.short_name, short_name = entry.short_name }
      end
      return out
    end
    local vpat = compile_pattern(query)
    if not vpat then
      return {}
    end
    local max_visible = math.max(1, vim.o.lines - 2)
    local results = {}
    for _, entry in ipairs(snap) do
      local ok, lines = pcall(vim.api.nvim_buf_get_lines, entry.bufnr, 0, -1, false)
      if ok and lines then
        for ln, line in ipairs(lines) do
          local found = vim.fn.matchstrpos(line, vpat, 0, 1)
          if found[2] and found[2] >= 0 then
            local label = entry.short_name .. ':' .. ln .. ':' .. line
            local short_bytes = #entry.short_name
            local line_str = tostring(ln)
            local prefix_bytes = short_bytes + #line_str + 2
            local label_bytes = #label
            local g = {
              bufnr = entry.bufnr,
              short_name = entry.short_name,
              line = ln,
              label = label,
              marks = {
                { start = 0, finish = short_bytes, group = 'LustyGrepFileName' },
                { start = short_bytes + 1, finish = prefix_bytes - 1, group = 'LustyGrepLineNumber' },
                { start = prefix_bytes, finish = label_bytes, group = 'LustyGrepContext' },
                { start = prefix_bytes + found[2], finish = prefix_bytes + found[3], group = 'LustyGrepMatch' },
              },
            }
            results[#results + 1] = g
            if #results >= max_visible then
              return results
            end
          end
        end
      end
    end
    return results
  end
end

function M.run()
  if running then
    return
  end
  running = true
  explorer.ensure_highlights()
  -- LustyGrepContext is used by the marks but has no link in the Lua
  -- port highlight map; make sure it exists.
  pcall(vim.api.nvim_set_hl, 0, 'LustyGrepContext', { link = 'Comment', default = true })
  local snap = buffers.compute_buffer_entries()
  local last_input = previous_input
  pick.pick({
    title = 'Buffer Grep',
    single_column = true,
    query = last_input,
    source = make_source(snap),
    on_open = function(item, mode)
      running = false
      open_grep_entry(item, mode)
    end,
    on_close = function(p)
      running = false
      if p and p.query then
        previous_input = p.query
      end
    end,
  })
end

function M.is_running()
  return running
end

M.translate_regex = lua_grep.translate_regex

return M
