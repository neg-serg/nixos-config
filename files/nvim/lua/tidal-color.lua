-- Bright TidalCycles highlighting for *.tidal buffers.
--
-- tidal.nvim sets the buffer filetype to `haskell`, so a plain syntax or
-- treesitter theme cannot tell `d1` from any other variable. This module
-- scans the buffer and paints:
--   * orbits d1..d16 with a rainbow of colors (wrap after 10)
--   * the operators `$` and `#` in hot orange
--   * Tidal control params (sound, note, gain, pan, ...) in bright mint
--
-- Implemented with extmarks (buffer-scoped, window-independent), re-scanned
-- on edits with a small debounce. Comments and string literals are skipped.

local M = {}

local ns = vim.api.nvim_create_namespace('TidalColor')

local ORBIT_COLORS = {
  '#ff6b6b', -- d1  red
  '#ffa94d', -- d2  orange
  '#ffd43b', -- d3  yellow
  '#69db7c', -- d4  green
  '#38d9a9', -- d5  teal
  '#4dabf7', -- d6  blue
  '#748ffc', -- d7  indigo
  '#da77f2', -- d8  purple
  '#f783ac', -- d9  pink
  '#ff8787', -- d10 light red
}

local PARAM_RE = [[\v<(sound|note|n|s|gain|pan|room|size|delay|delaytime|delayfeedback|lpf|hpf|bandf|crush|shape|speed|sustain|release|attack|cutoff|orbit|amp|legato|vowel|slide|accelerate|begin|end|stut|echo|jux|rev|fast|slow|every|sometimes|struct|iter|palindrome|scramble)>]]
local OP_RE = [=[\v[\$#]]=]

-- Skip highlighting when the position is inside a string/comment per treesitter.
local function ts_skip(buf, line, col)
  local ok, node = pcall(vim.treesitter.get_node, {
    buf = buf,
    pos = { line, col },
  })
  if not ok or not node then
    return false
  end
  local t = node:type()
  return t == 'string' or t == 'comment' or t == 'char'
end

local function paint(buf)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)

  for ln, text in ipairs(lines) do
    -- orbits d1..d16 with word boundaries
    for start_pos, num in text:gmatch('()d(%d+)') do
      local n = tonumber(num)
      if n and n >= 1 and n <= 16 then
        local before = start_pos > 1 and text:sub(start_pos - 1, start_pos - 1) or ''
        local after_pos = start_pos + 1 + #num
        local after = text:sub(after_pos, after_pos)
        if not before:match('[%w_]') and not after:match('[%w_]') then
          if not ts_skip(buf, ln - 1, start_pos - 1) then
            local idx = ((n - 1) % #ORBIT_COLORS) + 1
            vim.api.nvim_buf_add_highlight(
              buf,
              ns,
              'TidalOrbit' .. idx,
              ln - 1,
              start_pos - 1,
              start_pos - 1 + 1 + #num
            )
          end
        end
      end
    end

    -- control params
    local pos = 1
    while true do
      local s, e = text:find(PARAM_RE, pos)
      if not s then
        break
      end
      if not ts_skip(buf, ln - 1, s - 1) then
        vim.api.nvim_buf_add_highlight(buf, ns, 'TidalParam', ln - 1, s - 1, e)
      end
      pos = e + 1
    end

    -- operators $ and #
    pos = 1
    while true do
      local s, e = text:find(OP_RE, pos)
      if not s then
        break
      end
      if not ts_skip(buf, ln - 1, s - 1) then
        vim.api.nvim_buf_add_highlight(buf, ns, 'TidalOp', ln - 1, s - 1, e)
      end
      pos = e + 1
    end
  end
end

local debounce = vim.uv or vim.loop
local timer

function M.setup()
  for i, color in ipairs(ORBIT_COLORS) do
    vim.api.nvim_set_hl(0, 'TidalOrbit' .. i, { fg = color, bold = true })
  end
  vim.api.nvim_set_hl(0, 'TidalParam', { fg = '#63e6be', bold = true })
  vim.api.nvim_set_hl(0, 'TidalOp', { fg = '#ff922b', bold = true })

  local function schedule_paint(buf)
    if timer then
      timer:stop()
    end
    timer = debounce.new_timer()
    timer:start(80, 0, function()
      vim.schedule(function()
        if vim.api.nvim_buf_is_valid(buf) then
          pcall(paint, buf)
        end
      end)
    end)
  end

  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    pattern = { '*.tidal' },
    callback = function(args)
      schedule_paint(args.buf)
    end,
  })
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    pattern = { '*.tidal' },
    callback = function(args)
      schedule_paint(args.buf)
    end,
  })
end

return M
