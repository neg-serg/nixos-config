-- Path/glob helpers for the LustyExplorer port.
-- Mirrors the behaviour of lusty.rb / file-masks.rb from sjbach/lusty.

local M = {}

local SEP = '/'

function M.ends_with(s, suffix)
  return suffix == '' or s:sub(-#suffix) == suffix
end

function M.starts_with(s, prefix)
  return s:sub(1, #prefix) == prefix
end

--- Basename of a path (Ruby File.basename semantics for our use cases).
function M.basename(s)
  if s == '' or s == nil then
    return ''
  end
  return s:match('([^/]*)$')
end

--- Dirname of a path (Ruby File.dirname semantics for our use cases).
function M.dirname(s)
  if s == nil or s == '' then
    return '.'
  end
  if s == '/' then
    return '/'
  end
  if s:sub(1, 1) ~= '/' and not s:find('/', 1, true) then
    return '.'
  end
  local stripped = s:gsub('/+$', '')
  if stripped == '' then
    return '/'
  end
  local d = stripped:match('^(.*)/[^/]*$')
  if not d or d == '' then
    return '/'
  end
  return d
end

--- Collapse redundant slashes and expand a leading tilde (~ or ~user).
local function expand_tilde_and_slashes(s)
  local out = s:gsub('/+', '/')
  if out:sub(1, 1) == '~' then
    local head = out:match('^~[^/]*')
    local rest = out:sub(#head + 1)
    local ex = vim.fn.expand(head)
    if ex and ex ~= '' and ex ~= head then
      out = ex .. rest
    end
  end
  return out
end

--- Lexical absolute path for existing/partial paths (expand_path-ish).
--- vim.fn.fnamemodify('X', ':p') keeps a trailing slash for directory-like input.
local function absolute(s)
  if s == '' then
    return vim.fn.fnamemodify('.', ':p')
  end
  local r = vim.fn.fnamemodify(s, ':p')
  if r == '' then
    r = s
  end
  return r
end

--- simplify_path() from lusty.rb.
--- @param s string raw prompt input (already $-expanded)
--- @return string canonical path
function M.simplify_path(s)
  if M.starts_with(s, 'scp://') then
    return s
  end
  s = expand_tilde_and_slashes(s)

  if s == '/' then
    return '/'
  end

  if M.ends_with(s, SEP) then
    local abs = absolute(s)
    if abs ~= '/' and not M.ends_with(abs, SEP) then
      abs = abs .. SEP
    end
    return abs
  end

  -- File-ish path (possibly partial): expand its directory part, keep the
  -- basename as typed (same as File.dirname/File.basename + expand_path).
  local d = M.dirname(s)
  local b = M.basename(s)
  local de = absolute(d)
  de = de:gsub('/+$', '')
  if de == '' then
    de = '/'
  end
  if de == '/' then
    return de .. b
  end
  return de .. SEP .. b
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

--- Convert a wildignore mask to a Lua pattern anchored at both ends.
--- Supports '*', '?' and simple '[...]' classes.
local function glob_to_lua_pattern(mask)
  local out = { '^' }
  local i = 1
  local n = #mask
  while i <= n do
    local c = mask:sub(i, i)
    if c == '*' then
      out[#out + 1] = '.*'
    elseif c == '?' then
      out[#out + 1] = '.'
    elseif c == '[' then
      local close = mask:find(']', i + 1, true)
      if close then
        local inner = mask:sub(i + 1, close - 1)
        if inner:sub(1, 1) == '!' then
          inner = '^' .. inner:sub(2)
        end
        out[#out + 1] = '[' .. inner .. ']'
        i = close
      else
        out[#out + 1] = '%['
      end
    elseif c:find('[%^%$%(%)%%%.%+%-]') then
      out[#out + 1] = '%' .. c
    else
      out[#out + 1] = c
    end
    i = i + 1
  end
  out[#out + 1] = '$'
  return table.concat(out)
end

--- FileMasks.masked? - does str match any mask?
function M.masked(str, masks)
  for _, mask in ipairs(masks) do
    if mask ~= '' then
      local pat = glob_to_lua_pattern(mask)
      if str:find(pat) then
        return true
      end
    end
  end
  return false
end

--- Read masks from g:LustyExplorerFileMasks (deprecated) or &wildignore.
function M.read_masks()
  local v = vim.g.LustyExplorerFileMasks
  if v ~= nil then
    if type(v) == 'string' then
      return vim.split(v, ',')
    end
    return v
  end
  return vim.split(vim.o.wildignore or '', ',')
end

return M

