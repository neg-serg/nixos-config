-- Path helpers for the Lusty pickers.
--
-- Only the pieces the native pickers still use live here; the path/glob
-- helpers that existed for the removed Lua port (simplify_path, FileMasks
-- matching, dirname) were dropped with it.

local M = {}

--- Basename of a path (Ruby File.basename semantics for our use cases).
function M.basename(s)
  if s == '' or s == nil then
    return ''
  end
  return s:match('([^/]*)$')
end

--- Longest common prefix of a list of paths, trimmed to the last '/'.
--- (LustyM::longest_common_prefix)
function M.longest_common_prefix(paths)
  if #paths == 0 then
    return ''
  end
  local prefix = paths[1]
  for i = 2, #paths do
    local p = paths[i]
    local n = math.min(#prefix, #p)
    local j = 1
    while j <= n and prefix:byte(j) == p:byte(j) do
      j = j + 1
    end
    if j <= n then
      prefix = prefix:sub(1, j - 1)
    elseif #p <= #prefix then
      prefix = prefix:sub(1, #p)
    end
    if prefix == '' then
      break
    end
    local last = prefix:match('.*()/')
    if last then
      prefix = prefix:sub(1, last)
    end
  end
  return prefix
end

return M
