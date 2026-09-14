-- Minimal reader for the Lusty theme TOML (files/nvim/lua/lusty/theme.toml).
-- The file uses only simple 'key = value' lines under [lusty.selection] /
-- [lusty.match], so a plain line parser is enough (no TOML dependency).

local M = {}

local function parse()
  local out = { selection = {}, match = {} }
  -- LUSTY_THEME overrides the file (the Rust reader honours it too), so the
  -- parity smoke can point both interfaces at one fixture.
  local path = os.getenv('LUSTY_THEME')
  if not path or path == '' then
    path = vim.fn.stdpath('config') .. '/lua/lusty/theme.toml'
  end
  local ok, data = pcall(vim.fn.readfile, path)
  if not ok or not data then
    return out
  end
  local sec = nil
  for _, raw in ipairs(data) do
    local line = raw:gsub('%s+$', '')
    if line:match('^%[') then
      sec = line:match('^%[([^]]+)%]')
    elseif sec == 'lusty.selection' or sec == 'lusty.match' then
      local key, val = line:match('^%s*(%w+)%s*=%s*(.+)$')
      if key then
        local target = out[sec == 'lusty.selection' and 'selection' or 'match']
        local quoted = val:gsub('^%s*', ''):gsub('%s*$', ''):match('^%"(.*)"%s*$')
        if quoted then
          target[key] = quoted
        elseif val:gsub('%s', '') == 'true' then
          target[key] = true
        elseif val:gsub('%s', '') == 'false' then
          target[key] = false
        end
      end
    end
  end
  return out
end

function M.selection()
  return parse().selection
end

function M.match()
  return parse().match
end

return M
