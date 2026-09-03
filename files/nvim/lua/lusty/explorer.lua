-- Base explorer engine: window/display/key handling for the LustyExplorer port.
-- Behavioural port of lusty/src/lusty/{explorer,display,prompt,saved-settings,
-- window}.rb from github.com/sjbach/lusty (Stephen Bach, Matt Tolton).

local util = require('lusty.util')

local M = {}

local COLUMN_SEPARATOR = '    '
local NO_MATCHES = '-- NO MATCHES --'
local TRUNCATED = '-- TRUNCATED --'
local PROMPT_PREFIX = '>> '

local ns = vim.api.nvim_create_namespace('lusty_explorer')

-- ---------------------------------------------------------------------------
-- Highlight groups (linked once, colours come from the active colorscheme).

local HL_LINKS = {
  LustyDir = 'Directory',
  LustySlash = 'Function',
  LustySelected = 'Type',
  LustyModified = 'Special',
  LustyCurrentBuffer = 'Constant',
  LustyGrepMatch = 'IncSearch',
  LustyGrepLineNumber = 'Directory',
  LustyGrepFileName = 'Comment',
  LustyOpenedFile = 'PreProc',
  LustyNoEntries = 'ErrorMsg',
  LustyTruncated = 'Visual',
  LustyPrompt = 'Comment',
}

function M.ensure_highlights()
  for name, link in pairs(HL_LINKS) do
    vim.api.nvim_set_hl(0, name, { link = link, default = true })
  end
end

-- Options (g:Lusty*), with sane defaults and clamping.
local function opt_number(name, default, lo, hi)
  local v = vim.g[name]
  if type(v) ~= 'number' then
    v = tonumber(v)
  end
  if type(v) ~= 'number' or v ~= v then
    return default
  end
  return math.max(lo, math.min(hi, v))
end

-- g:LustyExplorerShowColors = 0 disables the dircolors cell coloring.
local function colors_enabled()
  local v = vim.g.LustyExplorerShowColors
  return not (v == false or v == 0 or v == '0')
end

-- g:LustyExplorerGravity: 'top' | 'center' (default) | 'bottom'.
local function gravity_value()
  local v = tostring(vim.g.LustyExplorerGravity or ''):lower()
  if v == 'top' or v == 'bottom' then
    return v
  end
  return 'center'
end

-- Vertical anchor of the float for a given height (editor lines).
local function gravity_row(n_lines, height, gravity)
  local margin = math.max(2, math.floor(n_lines * 0.05))
  if gravity == 'top' then
    return margin
  elseif gravity == 'bottom' then
    return math.max(0, n_lines - height - margin)
  end
  return math.max(0, math.floor((n_lines - height) / 2))
end

-- ---------------------------------------------------------------------------
-- Prompt.

local Prompt = {}
Prompt.__index = Prompt

function Prompt.new(filesystem)
  return setmetatable({ input = '', filesystem = filesystem or false }, Prompt)
end

function Prompt:set(s)
  self.input = s or ''
end

function Prompt:clear()
  self.input = ''
end

function Prompt:add(s)
  self.input = self.input .. s
end

function Prompt:backspace()
  self.input = self.input:sub(1, -2)
end

-- Chop the last path component (C-w), mirroring Prompt#up_one_dir!.
function Prompt:up_one_dir()
  local s = self.input:gsub('/+$', '') -- drop a trailing slash first
  local pos = s:match('.*()/')
  if pos then
    self.input = s:sub(1, pos)
  else
    self.input = ''
  end
end

function Prompt:ends_with(c)
  return self.input:sub(-1) == c
end

function Prompt:at_dir()
  return self.input == '' or self.input:sub(-1) == '/'
end

local function expand_env(s)
  return (s:gsub('%$([%w_]+)', function(w)
    local v = vim.fn.getenv(w)
    if v and v ~= vim.NIL then
      return v
    end
  end))
end

-- Canonical input used by the explorers.
function Prompt:value()
  if not self.filesystem then
    return self.input
  end
  return util.simplify_path(expand_env(self.input))
end

function Prompt:basename()
  return util.basename(self:value())
end

function Prompt:dirname()
  return util.dirname(self:value())
end

-- ---------------------------------------------------------------------------
-- Explorer base object.

local Explorer = {}
Explorer.__index = Explorer

function Explorer.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Explorer)
  self.title = opts.title or 'LustyExplorer'
  self.single_column = opts.single_column or false
  self.prompt = Prompt.new(opts.filesystem or false)
  self.matches = {}
  self.selected = 0
  self.row_count = nil
  self.running = false
  self.win_id = nil
  self.buf_id = nil
  self.calling_win = nil
  self.calling_buf = nil
  self.float_width = nil
  self.float_max_height = nil
  self.augroup = nil
  return self
end

-- ---------------------------------------------------------------------------
-- Layout helpers (display.rb).

local function sw(s)
  return vim.fn.strwidth(s)
end

local function center(text, width)
  local pad = math.max(0, width - sw(text))
  local l = math.floor(pad / 2)
  local r = pad - l
  return string.rep(' ', l) .. text .. string.rep(' ', r)
end

local function displayable_upper_bound(strings, max_w, max_h)
  local lens = {}
  for _, s in ipairs(strings) do
    lens[#lens + 1] = #s
  end
  table.sort(lens)
  local longest = table.remove(lens) or 0
  local row_width = longest + #COLUMN_SEPARATOR
  local col_count = 1
  for _, len in ipairs(lens) do
    row_width = row_width + len
    if row_width > max_w then
      break
    end
    col_count = col_count + 1
    row_width = row_width + #COLUMN_SEPARATOR
  end
  return col_count * max_h
end

-- Column width for the strings in the given (1-based, inclusive) range.
local function range_width(strings, first, last)
  local w = 0
  for i = first, last do
    local x = sw(strings[i])
    if x > w then
      w = x
    end
  end
  return w
end

-- Binary search over row counts (compute_optimal_row_count).
local function optimal_row_count(strings, max_h, max_w)
  local lower = 1
  local upper = max_h + 1
  while lower + 1 ~= upper do
    local rc = math.floor((lower + upper) / 2)
    local idx = 1
    local total = 0
    local fits = true
    while idx <= #strings do
      local last = math.min(idx + rc - 1, #strings)
      total = total + range_width(strings, idx, last)
      if total > max_w then
        fits = false
        break
      end
      total = total + #COLUMN_SEPARATOR
      idx = idx + rc
    end
    if fits then
      total = total - #COLUMN_SEPARATOR
    end
    if fits and total <= max_w then
      upper = rc
    else
      lower = rc
    end
  end
  if upper > max_h then
    return max_h - 1, true
  end
  return upper, false
end

--- Return (row_count, column_widths, truncated) for a set of labels.
local function compute_layout(strings, single_column, max_w, max_h)
  local rows
  local trunc = false
  if single_column then
    if #strings <= max_h then
      rows = #strings
    else
      rows = max_h - 1
      trunc = true
    end
  elseif #strings > displayable_upper_bound(strings, max_w, max_h) then
    rows = max_h - 1
    trunc = true
  else
    local single_row_width = 0
    for _, s in ipairs(strings) do
      single_row_width = single_row_width + #COLUMN_SEPARATOR + #s
    end
    if single_row_width <= max_w or #strings == 1 then
      rows = 1
    else
      rows, trunc = optimal_row_count(strings, max_h, max_w)
    end
  end

  -- Prefer a tall listing over squeezing everything into a few dense rows.
  -- Target roughly 60% of the screen height (more rows = fewer columns,
  -- which always still fits the window width).  With fewer entries than the
  -- target, show one entry per row.
  if not single_column and not trunc then
    local want = math.min(#strings, math.max(6, math.floor(max_h * 0.6)))
    if want > rows then
      rows = want
    end
  end

  -- Column widths; stop adding columns once the window width is exhausted.
  local widths = {}
  local total_width = 0
  local idx = 1
  while idx <= #strings do
    local last = math.min(idx + rows - 1, #strings)
    local w = range_width(strings, idx, last)
    total_width = total_width + w
    if total_width > max_w then
      break
    end
    widths[#widths + 1] = w
    total_width = total_width + #COLUMN_SEPARATOR
    idx = idx + rows
  end
  if #widths == 0 and #strings > 0 then
    local w = range_width(strings, 1, math.min(rows, #strings))
    widths = { w }
  end

  return rows, widths, trunc
end

-- ---------------------------------------------------------------------------
-- Rendering.

-- Build buffer lines for the current matches.  Returns:
--   lines   - display lines (no prompt line yet)
--   cells   - per line: { text, { {byte_start, byte_end, entry_idx, content} } }
--   rows    - layout row count (nil when empty)
--   trunc   - whether a truncated indicator was appended
local function render(self, strings)
  local max_w = self.float_width or vim.o.columns
  -- Rows budget: the float keeps table rows + truncation line + prompt line
  -- inside float_max_height (borders excluded), so nothing is cut off.
  local budget = self.float_max_height or (vim.o.lines - 2)
  local max_h = math.max(1, budget - 2)

  if #strings == 0 then
    return { center(NO_MATCHES, max_w) }, {}, nil, false, true
  end

  local rows, widths, trunc = compute_layout(strings, self.single_column, max_w, max_h)
  local lines = {}
  local cells = {}
  for r = 1, rows do
    local parts = {}
    local line_cells = {}
    local byte_pos = 0
    for c = 1, #widths do
      local idx = (c - 1) * rows + r
      if idx <= #strings then
        local content = strings[idx]
        local pad = widths[c] - sw(content)
        if pad < 0 then
          pad = 0
        end
        parts[#parts + 1] = content
        parts[#parts + 1] = string.rep(' ', pad)
        if c < #widths then
          parts[#parts + 1] = COLUMN_SEPARATOR
        end
        local bstart = byte_pos + 1
        byte_pos = byte_pos + #content
        line_cells[#line_cells + 1] = {
          byte_start = bstart,
          byte_end = byte_pos,
          entry_idx = idx,
          content = content,
        }
        byte_pos = byte_pos + pad
        if c < #widths then
          byte_pos = byte_pos + #COLUMN_SEPARATOR
        end
      end
    end
    lines[r] = table.concat(parts)
    cells[r] = line_cells
  end

  if trunc then
    lines[#lines + 1] = center(TRUNCATED, max_w)
    cells[#cells + 1] = {}
  end

  return lines, cells, rows, trunc, false
end

local function prompt_text(self)
  local body = self.prompt.input
  local t = PROMPT_PREFIX .. body
  local max_w = (self.float_width or vim.o.columns) - 5
  if max_w > 0 and sw(t) > max_w then
    -- Keep the tail (like Prompt#print) so the query stays readable,
    -- dropping whole characters (never split UTF-8 in half).
    local keep = math.max(1, max_w - 3)
    local nchars = vim.fn.strchars(t)
    while #t > keep and nchars > 1 do
      t = vim.fn.strcharpart(t, 1, nchars - 1)
      nchars = nchars - 1
    end
    t = '...' .. t
  end
  return t
end

local function write_buffer(self, lines)
  if not (self.buf_id and vim.api.nvim_buf_is_valid(self.buf_id)) then
    return
  end
  local buf = self.buf_id
  local ok = pcall(vim.api.nvim_buf_set_option, buf, 'modifiable', true)
  if not ok then
    return
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_set_option(buf, 'modifiable', false)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
end

-- Paint extmarks for the current buffer contents.
local function paint(self, cells)
  if not (self.buf_id and vim.api.nvim_buf_is_valid(self.buf_id)) then
    return
  end
  local buf = self.buf_id
  -- nvim_buf_add_highlight(buffer, ns, group, line, col_start, col_end):
  -- a highlight spans one line only (no end_row parameter).
  local function hl(line, col_start, col_end, group)
    pcall(vim.api.nvim_buf_add_highlight, buf, ns, group, line, col_start, col_end)
  end

  for row_idx, line_cells in ipairs(cells) do
    local line = row_idx - 1
    for _, cell in ipairs(line_cells) do
      local entry = self.matches[cell.entry_idx]
      if entry then
        -- dircolors-style coloring (LS_COLORS) when the explorer provides a
        -- color resolver (unless disabled via g:LustyExplorerShowColors);
        -- falls back to the static LustyDir/LustySlash marks.
        local color_group = colors_enabled() and self.color_entry and self.color_entry(entry) or nil
        if color_group then
          hl(line, cell.byte_start - 1, cell.byte_end, color_group)
        else
          -- Directory/path prefix part (LustyDir + contained LustySlash).
          local slash = not entry.no_dir_hl and cell.content:match('.*()/') or nil
          if slash then
            hl(line, cell.byte_start - 1, cell.byte_start - 1 + slash, 'LustySlash')
            hl(line, cell.byte_start - 1, cell.byte_start - 1 + slash, 'LustyDir')
          end
        end
        if entry.modified then
          local b = cell.content:find(' [+]', 1, true)
          if b then
            hl(line, cell.byte_start - 1 + b - 1, cell.byte_end, 'LustyModified')
          end
        end
        if entry.is_current then
          hl(line, cell.byte_start - 1, cell.byte_end, 'LustyCurrentBuffer')
        end
        -- Subclass-provided marks (e.g. grep match/context splits).
        if entry.marks then
          for _, m in ipairs(entry.marks) do
            if m.group then
              hl(line, cell.byte_start - 1 + m.start, cell.byte_start - 1 + m.finish, m.group)
            end
          end
        end
      end
    end
  end

  -- Selected entry (whole cell).
  local selected = self.selected + 1
  for row_idx, line_cells in ipairs(cells) do
    for _, cell in ipairs(line_cells) do
      if cell.entry_idx == selected then
        hl(row_idx - 1, cell.byte_start - 1, cell.byte_end, 'LustySelected')
      end
    end
  end

  -- Prompt line is the last line: '>> ' plus the typed query.
  local last = vim.api.nvim_buf_line_count(buf) - 1
  if last >= 0 then
    hl(last, 0, #PROMPT_PREFIX, 'LustyPrompt')
  end
end

function Explorer:refresh(mode)
  if not self.running then
    return
  end
  if mode == 'full' then
    self.matches = self:compute_sorted_matches()
  end
  local strings = {}
  for _, e in ipairs(self.matches) do
    strings[#strings + 1] = e.label
  end

  local lines, cells, rows, trunc, no_entries = render(self, strings)
  lines[#lines + 1] = prompt_text(self)
  write_buffer(self, lines)

  -- Size and re-anchor the float (gravity-aware): table rows + (truncated
  -- line) + prompt.
  local height = math.min(#lines, self.float_max_height or math.max(6, vim.o.lines - 2))
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    local outer_w = (self.float_width or vim.o.columns) + 2 -- rounded border
    pcall(vim.api.nvim_win_set_config, self.win_id, {
      relative = 'editor', -- required when reconfiguring a float
      width = outer_w,
      height = height,
      row = gravity_row(vim.o.lines, height, self.gravity or 'center'),
      col = math.max(0, math.floor((vim.o.columns - outer_w) / 2)),
    })
  end

  self.row_count = no_entries and nil or rows
  self.cells = cells
  paint(self, cells)

  -- Hide the cursor in the bottom-right corner.
  if self.win_id and vim.api.nvim_win_is_valid(self.win_id) then
    local count = vim.api.nvim_buf_line_count(self.buf_id)
    local last_line = vim.api.nvim_buf_get_lines(self.buf_id, count - 1, count, false)[1] or ''
    pcall(vim.api.nvim_win_set_cursor, self.win_id, { count, #last_line })
  end
end

-- ---------------------------------------------------------------------------
-- Key handling (explorer.rb key_pressed).

local function column_nav(self, delta)
  if not self.row_count or self.row_count == 0 then
    self.selected = 0
    return
  end
  local n = #self.matches
  if n == 0 then
    self.selected = 0
    return
  end
  local columns = math.ceil(n / self.row_count)
  local cur_column = math.floor(self.selected / self.row_count)
  local cur_row = self.selected % self.row_count
  local new_column = (cur_column + delta) % columns
  if (new_column + 1) * (cur_row + 1) > n then
    new_column = delta > 0 and 0 or math.max(0, columns - 2)
  end
  self.selected = new_column * self.row_count + cur_row
  if self.selected >= n then
    self.selected = n - 1
  end
end

function Explorer:key_pressed(code)
  if not self.running then
    return
  end
  local mode = 'full'
  local handled = true

  if code >= 32 and code <= 126 then
    self.prompt:add(string.char(code))
    self.selected = 0
  elseif code == 8 then
    self.prompt:backspace()
    self.selected = 0
  elseif code == 9 or code == 13 then
    self:choose('current_tab')
  elseif code == 23 then
    self.prompt:up_one_dir()
    self.selected = 0
  elseif code == 14 then
    local n = #self.matches
    self.selected = n == 0 and 0 or ((self.selected + 1) % n)
    mode = 'no_recompute'
  elseif code == 16 then
    local n = #self.matches
    self.selected = n == 0 and 0 or ((self.selected - 1) % n)
    mode = 'no_recompute'
  elseif code == 6 then
    column_nav(self, 1)
    mode = 'no_recompute'
  elseif code == 2 then
    column_nav(self, -1)
    mode = 'no_recompute'
  elseif code == 15 then
    self:choose('new_split')
  elseif code == 20 then
    self:choose('new_tab')
  elseif code == 21 then
    self.prompt:clear()
    self.selected = 0
  elseif code == 22 then
    self:choose('new_vsplit')
  else
    handled = false
  end

  if handled then
    self:refresh(mode)
  end
end

function Explorer:choose(mode)
  local entry = self.matches[self.selected + 1]
  if not entry then
    return
  end
  self:open_entry(entry, mode)
end

-- ---------------------------------------------------------------------------
-- Window lifecycle.

local function set_buffer_opts(buf)
  local bo = {
    buftype = 'nofile',
    bufhidden = 'delete',
    swapfile = false,
    modifiable = false,
    buflisted = false,
    spell = false,
    textwidth = 0,
    filetype = '',
  }
  for k, v in pairs(bo) do
    pcall(vim.api.nvim_buf_set_option, buf, k, v)
  end
end

local function set_window_opts(win)
  local wo = {
    wrap = false,
    number = false,
    relativenumber = false,
    foldcolumn = '0',
    colorcolumn = '0',
    cursorline = false,
    cursorcolumn = false,
  }
  for k, v in pairs(wo) do
    pcall(vim.api.nvim_win_set_option, win, k, v)
  end
end

local function setup_keymaps(self)
  local buf = self.buf_id
  local function map(lhs, code, cancel)
    local opts = { nowait = true, silent = true, noremap = true }
    if cancel then
      opts.callback = function()
        self:cancel()
      end
    else
      opts.callback = function()
        self:key_pressed(code)
      end
    end
    pcall(vim.api.nvim_buf_set_keymap, buf, 'n', lhs, '', opts)
  end

  for code = 32, 126 do
    local ch = string.char(code)
    local lhs = ch
    if ch == '<' then
      lhs = '<lt>'
    elseif ch == '|' then
      lhs = '<Bar>'
    elseif ch == '\\' then
      lhs = '<Bslash>'
    end
    map(lhs, code)
  end

  -- Dual-layout support (langmapper-style): the user types on the RU
  -- (йцукен) layout, where the physical keys produce Cyrillic characters
  -- ('.' key -> 'ю', 'b' key -> 'и', '/' key -> '.' ...).  Register the RU
  -- characters so they feed the same EN query characters; langmap alone does
  -- not apply to keys that participate in mappings.
  local ru_to_en = {
    { 'й', 'q' }, { 'ц', 'w' }, { 'у', 'e' }, { 'к', 'r' }, { 'е', 't' },
    { 'н', 'y' }, { 'г', 'u' }, { 'ш', 'i' }, { 'щ', 'o' }, { 'з', 'p' },
    { 'х', '[' }, { 'ъ', ']' }, { 'ф', 'a' }, { 'ы', 's' }, { 'в', 'd' },
    { 'а', 'f' }, { 'п', 'g' }, { 'р', 'h' }, { 'о', 'j' }, { 'л', 'k' },
    { 'д', 'l' }, { 'ж', ';' }, { 'э', "'" }, { 'я', 'z' }, { 'ч', 'x' },
    { 'с', 'c' }, { 'м', 'v' }, { 'и', 'b' }, { 'т', 'n' }, { 'ь', 'm' },
    { 'б', ',' }, { 'ю', '.' }, { '.', '/' },
  }
  for _, pair in ipairs(ru_to_en) do
    map(pair[1], string.byte(pair[2]))
  end

  map('<Tab>', 9)
  map('<CR>', 13)
  map('<S-CR>', 10)
  map('<BS>', 8)
  map('<Del>', 8)
  map('<C-h>', 8)
  map('<C-a>', 1)
  map('<C-w>', 23)
  map('<C-n>', 14)
  map('<C-p>', 16)
  map('<C-f>', 6)
  map('<C-b>', 2)
  map('<C-o>', 15)
  map('<C-t>', 20)
  map('<C-u>', 21)
  map('<C-v>', 22)
  map('<C-e>', 5)
  map('<C-d>', 4)
  map('<C-r>', 18)
  map('<Left>', 2)
  map('<Right>', 6)
  map('<Up>', 16)
  map('<Down>', 14)
  map('<Esc>', nil, true)
  map('<C-c>', nil, true)
  map('<C-g>', nil, true)
end

function Explorer:create_window()
  self.calling_win = vim.fn.win_getid()
  self.calling_buf = vim.fn.bufnr('%')

  -- Floating window of comfortable size; the content layout uses the
  -- inner (border-less) width, sizing/centering is updated on every refresh.
  -- Ratios are configurable: g:LustyExplorerWidthRatio (default 0.9) and
  -- g:LustyExplorerMaxHeightRatio (default 0.8).
  local wratio = opt_number('LustyExplorerWidthRatio', 0.9, 0.4, 1.0)
  local hratio = opt_number('LustyExplorerMaxHeightRatio', 0.8, 0.3, 0.95)
  self.gravity = gravity_value()
  local outer_w = math.max(44, math.floor(vim.o.columns * wratio))
  self.float_width = math.max(40, outer_w - 2) -- minus the rounded border
  self.float_max_height = math.max(6, math.floor(vim.o.lines * hratio))

  self.buf_id = vim.api.nvim_create_buf(false, true)
  set_buffer_opts(self.buf_id)
  pcall(vim.api.nvim_buf_set_name, self.buf_id, self.title)

  self.win_id = vim.api.nvim_open_win(self.buf_id, true, {
    relative = 'editor',
    style = 'minimal',
    width = outer_w,
    height = 2,
    row = gravity_row(vim.o.lines, 2, self.gravity),
    col = math.max(0, math.floor((vim.o.columns - outer_w) / 2)),
    border = 'rounded',
  })
  set_window_opts(self.win_id)
  setup_keymaps(self)

  -- If the window gets closed some other way, unwind cleanly (same as cancel).
  self.augroup = vim.api.nvim_create_augroup('LustyExplorerPort_' .. self.win_id, { clear = true })
  vim.api.nvim_create_autocmd('WinClosed', {
    group = self.augroup,
    pattern = tostring(self.win_id),
    callback = function()
      if self.running then
        self:cancel()
      end
    end,
  })
end

-- Close the explorer float and return focus to the calling window.
function Explorer:cleanup()
  if not self.running then
    return
  end
  if self.on_cleanup then
    self.on_cleanup(self)
  end
  self.running = false

  local win = self.win_id
  local buf = self.buf_id
  self.win_id = nil
  self.buf_id = nil

  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  elseif buf and vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_is_loaded(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  if self.calling_win and vim.api.nvim_win_is_valid(self.calling_win) then
    pcall(vim.api.nvim_set_current_win, self.calling_win)
  end
end

-- Esc / <C-c> / <C-g>: just close the explorer and give focus back.
-- No buffer juggling: nvim keeps the caller's alternate/buffer state intact on
-- its own, and switching buffers here can error with E37 when 'hidden' is off.
function Explorer:cancel()
  if not self.running then
    return
  end
  self:cleanup()
  if vim.api.nvim_win_is_valid(self.calling_win) then
    pcall(vim.api.nvim_set_current_win, self.calling_win)
  end
end

function Explorer:start()
  if self.running then
    return
  end
  self.running = true
  local ok, err = pcall(function()
    self:create_window()
    self:refresh('full')
  end)
  if not ok then
    vim.notify('LustyExplorer: ' .. tostring(err), vim.log.levels.ERROR)
    self:cleanup()
  end
end

M.Explorer = Explorer
M.Prompt = Prompt
M.prompt_text = prompt_text

return M
