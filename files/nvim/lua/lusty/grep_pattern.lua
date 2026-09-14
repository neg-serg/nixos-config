-- Ruby-ish regex -> Vim 'magic' pattern for the buffer grep.
--
-- Ruby uses unescaped ( ) | + ? {n,m}; Vim magic needs \( \) \| \{n,m\}, and
-- \b \d \w \s are translated to Vim equivalents. The pattern always ends with
-- \c, so buffer grep is case-insensitive like the original LustyExplorer.
--
-- Extracted from the removed Lua-port BufferGrep; native_buffer_grep.lua is
-- the only consumer now.

local M = {}

--- Translate one Ruby-ish pattern to a Vim magic pattern.
--- @param re string
--- @return string vim pattern
function M.translate_regex(re)
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

return M
