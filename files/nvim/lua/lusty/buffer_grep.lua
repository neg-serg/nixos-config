-- BufferGrep: port of lusty/src/lusty/buffer-grep.rb.
-- Searches all loaded (listed) buffers with a Ruby-style regex.
-- The regex is translated to a Vim 'magic' pattern; searches are always
-- case-insensitive (as in the original).

local buffers = require('lusty.buffer_stack')
local E = require('lusty.explorer')

local M = {}

local e = E.Explorer.new({
  title = 'LustyExplorer--BufferGrep',
  single_column = true,
})


-- State carried between runs (like @previous_* in the original).
local previous = {
  input = '',
  entries = nil,
  selected = 0,
}
local pending = nil

-- ---------------------------------------------------------------------------
-- Ruby-ish regex -> Vim pattern (default 'magic' mode).
-- Ruby uses unescaped ( ) | + ? {n,m}; Vim magic needs \( \) \| \{n,m\}.
-- \b \d \w \s are translated to Vim equivalents. Case-insensitive always.

local function translate_regex(re)
  local out = {}
  local in_class = false
  local i = 1
  local n = #re
  while i <= n do
    local c = re:sub(i, i)
    if c == '\\' then
      local nx = re:sub(i + 1, i + 1)
      if nx == 'b' then
        -- Word boundary: \%( \< \| \> \) (magic-safe; escaped close).
        out[#out + 1] = '\\%(\\<\\|\\>\\)'
      elseif nx == 'd' then
        out[#out + 1] = '[0-9]'
      elseif nx == 'w' then
        out[#out + 1] = '[0-9A-Za-z_]'
      elseif nx == 's' then
        out[#out + 1] = '[ \t]'
      else
        out[#out + 1] = c .. nx
      end
      i = i + 2
    elseif in_class then
      out[#out + 1] = c
      if c == ']' then
        in_class = false
      end
      i = i + 1
    elseif c == '[' then
      in_class = true
      out[#out + 1] = c
      i = i + 1
    elseif c == '(' then
      out[#out + 1] = '\\('
      i = i + 1
    elseif c == ')' then
      out[#out + 1] = '\\)'
      i = i + 1
    elseif c == '|' then
      out[#out + 1] = '\\|'
      i = i + 1
    elseif c == '{' then
      out[#out + 1] = '\\{'
      i = i + 1
    elseif c == '}' then
      out[#out + 1] = '\\}'
      i = i + 1
    elseif c == '+' then
      -- In Vim magic '+' needs escaping (unlike Ruby).
      out[#out + 1] = '\\+'
      i = i + 1
    elseif c == '?' then
      out[#out + 1] = '\\?'
      i = i + 1
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out) .. '\\c'
end

local function compile_pattern(input)
  local ok, vpat = pcall(translate_regex, input)
  if not ok then
    return nil
  end
  local ok2, rx = pcall(vim.regex, vpat)
  if not ok2 or not rx then
    return nil
  end
  return vpat, rx
end

-- Grep run state.

local function prepare_entries()
  local entries = buffers.compute_buffer_entries()
  for _, entry in ipairs(entries) do
    entry.marks = nil
  end
  return entries
end

local function run_explorer()
  e.prompt:set(previous.input)
  e.entries = prepare_entries()
  e.selected = previous.selected
  e:start()
end

e.compute_sorted_matches = function(self)
  -- Right after a relaunch, show the previous grep results (no re-grep yet).
  if pending then
    local p = pending
    pending = nil
    return p
  end

  local abbrev = self.prompt.input
  if abbrev == '' then
    -- No query: list all buffers (labels = short names), like the original.
    for _, entry in ipairs(self.entries) do
      entry.label = entry.short_name
      entry.line = nil
      entry.marks = nil
    end
    return self.entries
  end

  local vpat, rx = compile_pattern(abbrev)
  if not vpat then
    return {}
  end

  local max_visible = math.max(1, vim.o.lines - 2)
  local results = {}

  for _, entry in ipairs(self.entries) do
    local ok, lines = pcall(vim.api.nvim_buf_get_lines, entry.bufnr, 0, -1, false)
    if ok and lines then
      for ln, line in ipairs(lines) do
        -- Note: matchstrpos {start} is 0-based in Neovim.
        local found = vim.fn.matchstrpos(line, vpat, 0, 1)
        if found[2] and found[2] >= 0 then
          local g = {
            bufnr = entry.bufnr,
            short_name = entry.short_name,
            line = ln,
            label = entry.short_name .. ':' .. ln .. ':' .. line,
            marks = nil,
            no_dir_hl = true,
          }
          -- Byte offsets inside the label:
          --   short_name ':' line ':' context
          local short_bytes = #entry.short_name
          local line_str = tostring(ln)
          local prefix_bytes = short_bytes + #line_str + 2
          local label_bytes = #g.label
          local mstart, mend = found[2], found[3] -- zero-based, end exclusive
          g.marks = {
            { start = 0, finish = short_bytes, group = 'LustyGrepFileName' },
            { start = short_bytes + 1, finish = prefix_bytes - 1, group = 'LustyGrepLineNumber' },
            { start = prefix_bytes, finish = label_bytes, group = 'LustyGrepContext' },
            { start = prefix_bytes + mstart, finish = prefix_bytes + mend, group = 'LustyGrepMatch' },
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

local function open_grep_entry(entry, mode)
  if mode == 'current_tab' then
    vim.cmd('silent b ' .. entry.bufnr)
  elseif mode == 'new_tab' then
    vim.cmd('silent tab split | b ' .. entry.bufnr)
  elseif mode == 'new_split' then
    vim.cmd('silent sp | b ' .. entry.bufnr)
  elseif mode == 'new_vsplit' then
    vim.cmd('silent vs | b ' .. entry.bufnr)
  end
  if entry.line then
    vim.cmd(tostring(entry.line))
  end
end

e.open_entry = function(self, entry, mode)
  self:cleanup()
  pcall(open_grep_entry, entry, mode)
end

-- Remember state across runs (BufferGrep#cleanup).
e.on_cleanup = function(self)
  previous.input = self.prompt.input
  previous.entries = self.matches
  previous.selected = self.selected
end

function M.run()
  if e.running then
    return
  end
  -- Carry the previous results into the first refresh of this run.
  pending = previous.entries
  run_explorer()
end

function M.explorer()
  return e
end

function M.translate_regex(re)
  return translate_regex(re)
end

return M
