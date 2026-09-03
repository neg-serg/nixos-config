-- dircolors-style coloring for LustyExplorer entries.
--
-- Reads LS_COLORS (as exported to Neovim) and paints file/dir cells like
-- 'ls --color=always' would: type codes first (di/ln/so/pi/ex/...), then
-- '*.ext' glob rules.  SGR codes (01;34, 38;5;N, 48;2;r;g;b ...) are
-- converted to Neovim highlight groups, cached per distinct style.

local M = {}

-- ---------------------------------------------------------------------------
-- SGR parsing.

-- Approximation of the standard xterm 16-color palette (used when a style
-- refers to 30..37/90..97 without truecolor/256 codes).
local BASIC16 = {
  '#000000', '#cd0000', '#00cd00', '#cdcd00', '#0000ee',
  '#cd00cd', '#00cdcd', '#e5e5e5',
  '#7f7f7f', '#ff0000', '#00ff00', '#ffff00', '#5c5cff',
  '#ff00ff', '#00ffff', '#ffffff',
}

local function cube6(v)
  -- 0..5 -> the six-level cube used by xterm 256-colour mode.
  return v == 0 and 0 or (55 + 40 * v)
end

local function xterm256(n)
  if n < 16 then
    return BASIC16[n + 1]
  elseif n < 232 then
    local c = n - 16
    local r = math.floor(c / 36)
    local g = math.floor((c % 36) / 6)
    local b = c % 6
    return string.format('#%02x%02x%02x', cube6(r), cube6(g), cube6(b))
  else
    local v = 8 + (n - 232) * 10
    return string.format('#%02x%02x%02x', v, v, v)
  end
end

--- Parse a SGR code string ('01;34', '38;5;123', '48;2;r;g;b', ...) into an
--- nvim_set_hl attribute table.  Returns nil when nothing useful is present.
local function parse_code(code)
  local parts = {}
  for p in vim.gsplit(code, ';', { plain = true }) do
    parts[#parts + 1] = p
  end
  local i = 1
  local n = #parts
  local hl = {}
  local fg_basic, fg_bright = nil, nil
  local bold = false

  local function num()
    if i > n then
      return nil
    end
    local v = tonumber(parts[i])
    i = i + 1
    return v
  end

  while i <= n do
    local c = num()
    if c == nil then
      break
    elseif c == 1 then
      bold = true
    elseif c == 3 then
      hl.italic = true
    elseif c == 4 then
      hl.underline = true
    elseif c == 7 then
      hl.reverse = true
    elseif c == 22 then
      bold = false
    elseif c == 23 then
      hl.italic = false
    elseif c == 24 then
      hl.underline = false
    elseif c == 27 then
      hl.reverse = false
    elseif c >= 30 and c <= 37 then
      fg_basic = c - 30
    elseif c >= 90 and c <= 97 then
      fg_bright = c - 90
      hl.fg = BASIC16[c - 90 + 9]
    elseif c >= 40 and c <= 47 then
      hl.bg = BASIC16[c - 40 + 1]
    elseif c >= 100 and c <= 107 then
      hl.bg = BASIC16[c - 100 + 9]
    elseif c == 38 then
      local mode = num()
      if mode == 5 then
        local idx = num()
        if idx then
          hl.fg = xterm256(idx)
        end
      elseif mode == 2 then
        local r, g, b = num(), num(), num()
        if r and g and b then
          hl.fg = string.format('#%02x%02x%02x', r, g, b)
        end
      end
    elseif c == 48 then
      local mode = num()
      if mode == 5 then
        local idx = num()
        if idx then
          hl.bg = xterm256(idx)
        end
      elseif mode == 2 then
        local r, g, b = num(), num(), num()
        if r and g and b then
          hl.bg = string.format('#%02x%02x%02x', r, g, b)
        end
      end
    end
  end

  -- dircolors writes e.g. 'di=01;34' (bold + base blue); terminals render
  -- that as the bright blue.  Emulate by shifting base fg to the bright set.
  if bold and not hl.fg and fg_basic then
    hl.fg = BASIC16[fg_basic + 9]
  elseif not bold and fg_basic then
    hl.fg = BASIC16[fg_basic + 1]
  end

  if bold then
    hl.bold = true
  end

  if hl.fg or hl.bg or hl.underline or hl.italic or hl.reverse then
    return hl
  end
  return nil
end

-- ---------------------------------------------------------------------------
-- LS_COLORS parsing.

local function lower_keep_classes(s)
  local out = {}
  local in_class = false
  for i = 1, #s do
    local c = s:sub(i, i)
    if in_class then
      out[#out + 1] = c
      if c == ']' then
        in_class = false
      end
    elseif c == '[' then
      in_class = true
      out[#out + 1] = c
    else
      out[#out + 1] = c:lower()
    end
  end
  return table.concat(out)
end

local function glob_to_pattern(glob)
  local out = { '^' }
  local in_class = false
  for i = 1, #glob do
    local c = glob:sub(i, i)
    if in_class then
      out[#out + 1] = c
      if c == ']' then
        in_class = false
      end
    elseif c == '*' then
      out[#out + 1] = '.*'
    elseif c == '?' then
      out[#out + 1] = '.'
    elseif c == '[' then
      in_class = true
      out[#out + 1] = c
    elseif c:find('[%^%$%(%)%%%.%+%-]') then
      out[#out + 1] = '%' .. c
    else
      out[#out + 1] = c
    end
  end
  out[#out + 1] = '$'
  return table.concat(out)
end

local function parse_ls_colors(env)
  local cfg = { types = {}, exts = {} }
  if not env or env == '' then
    return cfg
  end
  for _, item in ipairs(vim.split(env, ':')) do
    local k, v = item:match('^([^=]+)=(.*)$')
    if k and v then
      if #k == 2 then
        cfg.types[k] = v
      elseif k:sub(1, 1) == '*' then
        cfg.exts[#cfg.exts + 1] = {
          key = k,
          pattern = glob_to_pattern(lower_keep_classes(k)),
          code = v,
        }
      end
    end
  end
  return cfg
end

local cfg = nil
local hl_cache = {}
local hl_counter = 0
local colorscheme_hooked = false

local function ensure_colorscheme_hook()
  if colorscheme_hooked then
    return
  end
  colorscheme_hooked = true
  vim.api.nvim_create_autocmd('ColorScheme', {
    pattern = '*',
    callback = function()
      hl_cache = {}
    end,
  })
end

local function ensure_group(attrs)
  local key = vim.json.encode(attrs)
  if hl_cache[key] then
    return hl_cache[key]
  end
  ensure_colorscheme_hook()
  hl_counter = hl_counter + 1
  local name = 'LustyLs' .. hl_counter
  vim.api.nvim_set_hl(0, name, attrs)
  hl_cache[key] = name
  return name
end

local function load_config()
  if cfg then
    return cfg
  end
  -- Source of truth: LS_COLORS exported by the shell (dircolors).  Use it
  -- verbatim; no custom rules of our own are merged in.
  local env = vim.env.LS_COLORS
  if env == nil or env == '' then
    -- No inherited palette: prefer the user's own dircolors file (the same
    -- one the shell evals), then fall back to the stock GNU palette like
    -- plain 'ls --color'.
    local candidates = {}
    local user_file = vim.env.HOME .. '/.config/dircolors/dircolors'
    if vim.fn.filereadable(user_file) == 1 then
      candidates[#candidates + 1] = { 'dircolors', '-b', user_file }
    end
    candidates[#candidates + 1] = { 'dircolors', '-b' }
    for _, args in ipairs(candidates) do
      local ok, out = pcall(vim.fn.system, args)
      if ok and vim.v.shell_error == 0 and type(out) == 'string' then
        local exported = out:match('LS_COLORS="(.-)"') or out:match("LS_COLORS='(.-)'")
        if exported then
          env = exported
          break
        end
      end
    end
  end
  cfg = parse_ls_colors(env or '')
  return cfg
end

-- ---------------------------------------------------------------------------
-- Lookup.

--- Resolve the highlight group for one filesystem entry.
--- Entry fields understood: name, is_dir, is_link, is_socket, is_pipe,
--- is_block, is_char, is_exec (all optional booleans).
--- @param entry table
--- @return string|nil group name
function M.group_for(entry)
  if not entry or not entry.name then
    return nil
  end
  local c = load_config()
  local code

  if entry.is_link then
    code = c.types.ln
  elseif entry.is_dir then
    code = c.types.di
  elseif entry.is_socket then
    code = c.types.so
  elseif entry.is_pipe then
    code = c.types.pi
  elseif entry.is_block then
    code = c.types.bd
  elseif entry.is_char then
    code = c.types.cd
  end

  if not code and entry.is_exec then
    code = c.types.ex
  end

  if not code then
    local lname = lower_keep_classes(entry.name)
    for _, item in ipairs(c.exts) do
      if lname:match(item.pattern) then
        code = item.code
        break
      end
    end
  end

  if not code then
    return nil
  end

  local attrs = parse_code(code)
  if not attrs then
    return nil
  end
  return ensure_group(attrs)
end

-- Test/plumbing.
function M.reset()
  cfg = nil
  hl_cache = {}
end

return M
