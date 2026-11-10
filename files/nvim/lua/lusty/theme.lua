-- Minimal reader for the Lusty theme TOML (files/nvim/lua/lusty/theme.toml).
-- The file uses only simple `key = value` lines under [lusty.profile] and
-- [lusty.colors], so a plain line parser is enough (no TOML dependency).
--
-- The Rust front-end reads the same two sections (src/tui.rs) and dumps the
-- resolved values through `lusty --theme-map`; the parity smoke test compares
-- the two readers, so a new key must be added to both (and to the defaults
-- below, which mirror theme.toml so a missing file still renders like fzf).

local M = {}

local DEFAULTS = {
  profile = {
    prompt = '❯  ',
    pointer = '▶',
    marker = '✓',
    footer_underline = true,
  },
  colors = {
    bg = '#000000',
    fg = '#4f5d78',
    fg_current = '#8DA6B2',
    hl = '#546c8a',
    hl_current = '#005faf',
    border = '#0b2536',
    separator = '#0b2536',
    info = '#3f5876',
    input = '#6c7e96',
    prompt = '#005faf',
    pointer = '#005faf',
    marker = '#04141C',
    footer = '#ffffff',
    preview_fg = '#4f5d78',
  },
}

local function parse()
  local out = { profile = {}, colors = {} }
  -- LUSTY_THEME overrides the file (the Rust reader honours it too), so the
  -- parity smoke test can point both interfaces at one fixture.
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
    elseif sec == 'lusty.profile' or sec == 'lusty.colors' then
      -- %w does not cover '_': the colour roles (fg_current, hl_current,
      -- preview_fg) and footer_underline all carry one.
      local key, val = line:match('^%s*([%w_]+)%s*=%s*(.+)$')
      if key then
        local target = out[sec == 'lusty.profile' and 'profile' or 'colors']
        local quoted = val:match('^%s*"(.*)"%s*$')
        if quoted ~= nil then
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

local cache = nil

--- Resolved theme: the parsed sections merged over the built-in defaults.
function M.get()
  if cache then
    return cache
  end
  local parsed = parse()
  cache = { profile = {}, colors = {} }
  for sec, defaults in pairs(DEFAULTS) do
    for key, fallback in pairs(defaults) do
      local value = parsed[sec][key]
      -- `and/or` would turn a parsed `false` back into the fallback: test
      -- for nil explicitly.
      if value ~= nil then
        cache[sec][key] = value
      else
        cache[sec][key] = fallback
      end
    end
  end
  return cache
end

function M.profile()
  return M.get().profile
end

function M.colors()
  return M.get().colors
end

return M
