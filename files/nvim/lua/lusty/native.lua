-- Lusty picker: Rust backend (lusty serve) rendered as a normal
-- nvim floating window with real highlights. No terminal buffer involved, so
-- it renders reliably even when nvim itself runs inside a web xterm. This is
-- the only picker implementation (the historical Lua port was removed).
--
-- Backend protocol (plain lines, tab separated):
--   Q <from> <to> <query> [sort] -> "N <total>" + "W <maxw>" + "R <i> <kind> <label>\t<path>" rows + "E"
--                             sort: 0 name, 1 ext, 2 size, 3 time (C-y cycles)
--   M <mask> <index>...     -> "K <index> <meta>" per index + "E" (long view;
--                             mask bits 1 perm, 2 user, 4 size, 8 time)
--   F <score> <path>        frecency record, no reply (the client sends its
--                             journal once; the empty query then leads with the
--                             higher-scored paths inside each depth)
--   V <index> <w> <h>       -> "V <lines> <dim>" + one "L <text>" per row + "E"
--                             preview pane (C-r); the prefix keeps a content
--                             line equal to "E" from ending the response
-- The server also sends "X <caps>" right after the banner; the client only
-- sends V when it has seen the "preview" capability.
-- kind: d (dir) / f (file) / l (link). C-l toggles the long view, C-y cycles
-- the sort order, C-Space marks files (multi-select: Enter opens the marked
-- set, the first via edit and the rest via badd), C-e opens the typed text as
-- a new buffer, C-d cycles the search depth (1..6), C-r toggles the preview.
-- Backslash/TAB/LF inside a label, path or D name are escaped as \\, \t, \n
-- (reversed by `unescape` below), so a file name containing them cannot break
-- the framing; non-UTF8 paths travel as raw bytes.

local lsc = require('lusty.ls_colors')
local frecency = require('lusty.frecency')
local theme = require('lusty.theme')

local M = {}

local api = vim.api

-- Env-gated phase profiler: LUSTY_PROF_FILE=<path> appends relative-ms
-- timestamps per phase (key arrival, debounce fire, rerank, serve response,
-- draw). No-op unless the env var is set.
local prof_t0 = nil
local prof_path = os.getenv('LUSTY_PROF_FILE')
local function pf(tag)
  if not prof_path then
    return
  end
  if not prof_t0 then
    prof_t0 = vim.loop.hrtime()
  end
  local f = io.open(prof_path, 'a')
  if f then
    f:write(string.format('%.2f %s\n', (vim.loop.hrtime() - prof_t0) / 1e6, tag))
    f:close()
  end
end


local ns = api.nvim_create_namespace('lusty_native_ls')
local preview_ns = api.nvim_create_namespace('lusty_native_preview')

-- xterm-256 palette (16 base + 6x6x6 cube + 24 grays) as {r,g,b}. chafa emits
-- `38;5;N` when asked for 256 colours; truecolour `38;2;r;g;b` is used as is.
local XTERM = {}
do
  local base = {
    { 0, 0, 0 },
    { 128, 0, 0 },
    { 0, 128, 0 },
    { 128, 128, 0 },
    { 0, 0, 128 },
    { 128, 0, 128 },
    { 0, 128, 128 },
    { 192, 192, 192 },
    { 128, 128, 128 },
    { 255, 0, 0 },
    { 0, 255, 0 },
    { 255, 255, 0 },
    { 0, 0, 255 },
    { 255, 0, 255 },
    { 0, 255, 255 },
    { 255, 255, 255 },
  }
  for i = 0, 15 do
    XTERM[i] = base[i + 1]
  end
  local lv = { 0, 95, 135, 175, 215, 255 }
  for r = 0, 5 do
    for g = 0, 5 do
      for b = 0, 5 do
        XTERM[16 + 36 * r + 6 * g + b] = { lv[r + 1], lv[g + 1], lv[b + 1] }
      end
    end
  end
  for i = 0, 23 do
    local v = 8 + i * 10
    XTERM[232 + i] = { v, v, v }
  end
end

local preview_hl = {}
--- Highlight group for one preview colour, created on first use.
local function preview_color(kind, rgb)
  local hex = string.format('#%02x%02x%02x', rgb[1], rgb[2], rgb[3])
  local key = kind .. hex
  local group = preview_hl[key]
  if not group then
    group = 'LustyPreview' .. (kind == 'fg' and 'F' or 'B') .. hex:sub(2)
    api.nvim_set_hl(0, group, kind == 'fg' and { fg = hex } or { bg = hex })
    preview_hl[key] = group
  end
  return group
end

--- Split one preview row into display text and colour runs. Byte offsets are
--- returned because nvim highlights are byte-based and chafa symbols are
--- multibyte. Supports the SGR subset chafa emits: reset, 30-37/90-97,
--- 40-47/100-107, 38;5;N / 48;5;N and 38;2;r;g;b / 48;2;r;g;b.
local function parse_sgr(line)
  local text = {}
  local runs = {}
  local fg, bg
  local run_start = 0
  local off = 0
  local function close_run()
    if (fg or bg) and off > run_start then
      runs[#runs + 1] = { run_start, off, fg, bg }
    end
    run_start = off
  end
  local function push(s)
    for c in s:gmatch('.') do
      text[#text + 1] = c
      off = off + #c
    end
  end
  local pos = 1
  while true do
    local s, e, params = line:find('\27%[([%d;]*)m', pos)
    if not s then
      push(line:sub(pos))
      break
    end
    push(line:sub(pos, s - 1))
    close_run()
    local list = {}
    if params == '' then
      list[1] = '0'
    else
      for p in params:gmatch('[^;]+') do
        list[#list + 1] = p
      end
    end
    local j = 1
    while j <= #list do
      local code = tonumber(list[j])
      if code == 0 then
        fg, bg = nil, nil
      elseif code == 39 then
        fg = nil
      elseif code == 49 then
        bg = nil
      elseif code and code >= 30 and code <= 37 then
        fg = XTERM[code - 30]
      elseif code and code >= 90 and code <= 97 then
        fg = XTERM[code - 90 + 8]
      elseif code and code >= 40 and code <= 47 then
        bg = XTERM[code - 40]
      elseif code and code >= 100 and code <= 107 then
        bg = XTERM[code - 100 + 8]
      elseif code == 38 or code == 48 then
        local mode = tonumber(list[j + 1])
        if mode == 5 then
          local c = XTERM[tonumber(list[j + 2]) or -1]
          if c then
            if code == 38 then
              fg = c
            else
              bg = c
            end
          end
          j = j + 2
        elseif mode == 2 then
          local r, g, b = tonumber(list[j + 2]), tonumber(list[j + 3]), tonumber(list[j + 4])
          if r and g and b then
            local c = { r, g, b }
            if code == 38 then
              fg = c
            else
              bg = c
            end
          end
          j = j + 4
        end
      end
      j = j + 1
    end
    pos = e + 1
  end
  close_run()
  return table.concat(text), runs
end

--- RU (йцукен) layout to EN chars (physical keys under RU produce Cyrillic).
-- RU (йцукен) keymap table, shared with the other pickers (`lusty.ru2en`).
local RU2EN = require('lusty.ru2en')

local function basename(label)
  return label:match('([^/]+)$') or label
end

--- Reverse the serve-side byte escaping: backslash, TAB and LF inside a label
--- or path are written as `\\`, `\t`, `\n` so a file name containing them
--- cannot break the line protocol. Byte-wise, so non-UTF8 paths pass through.
---
--- `keep_controls` is used for display labels: a raw LF in a buffer line makes
--- nvim_buf_set_lines fail and a raw TAB breaks the grid pitch, so those stay
--- in their visible two-character form. Paths must be decoded fully — they are
--- handed to the filesystem verbatim.
local function decode_escape(n, keep_controls)
  if n == '\\' then
    return '\\'
  end
  if keep_controls then
    return '\\' .. n
  end
  if n == 't' then
    return '\t'
  end
  if n == 'n' then
    return '\n'
  end
  if n == 'r' then
    return '\r'
  end
  return n
end

local function unescape(s, keep_controls)
  if not s:find('\\', 1, true) then
    return s
  end
  local out = {}
  local i = 1
  while i <= #s do
    local c = s:sub(i, i)
    if c == '\\' and i < #s then
      out[#out + 1] = decode_escape(s:sub(i + 1, i + 1), keep_controls)
      i = i + 2
    else
      out[#out + 1] = c
      i = i + 1
    end
  end
  return table.concat(out)
end

--- Escape a path for the client-to-server direction (`F` frecency records);
--- reverse of `unescape` with the same three sequences.
local function escape(s)
  return (s:gsub('\\', '\\\\'):gsub('\t', '\\t'):gsub('\n', '\\n'))
end

-- serve Q sort token: 0 name, 1 ext, 2 size desc, 3 time desc (eza-style).
local SORT_LABELS = { 'name', 'ext', 'size', 'time' }

-- Nerd-font icons, same glyphs as the standalone TUI. Off by default:
-- enable with g:LustyExplorerIcons = 1 (or true) or LUSTY_ICONS=1.
-- Dirs-first/reverse mirror the standalone --dirs-first/--reverse CLI
-- options (they reshape the canonical name order only) and are read the
-- same way: env LUSTY_* wins over the g: counterpart (roadmap priority).
-- Nerd-font icons, single source of truth in `lusty.icons` (parity-checked
-- against the Rust table by `lusty --icon-map`).
local icons = require('lusty.icons')
local ICON_DIR = icons.dir

local function option_enabled(env, g)
  local e = os.getenv(env)
  if e ~= nil and e ~= '' then
    return e == '1' or e == 'true'
  end
  local gv = vim.g[g]
  if type(gv) == 'boolean' then
    return gv
  end
  if type(gv) == 'number' then
    return gv == 1
  end
  if type(gv) == 'string' then
    return gv == '1' or gv == 'true'
  end
  return false
end

local function icons_enabled()
  return option_enabled('LUSTY_ICONS', 'LustyExplorerIcons')
end

local function dirs_first_enabled()
  return option_enabled('LUSTY_DIRS_FIRST', 'LustyExplorerDirsFirst')
end

local function reverse_enabled()
  return option_enabled('LUSTY_REVERSE', 'LustyExplorerReverse')
end

--- Frecency ordering is on unless explicitly disabled: the empty-query listing
--- then leads with the files the user opens most (g:LustyExplorerFrecency = 0
--- or LUSTY_FRECENCY=0 turns it off).
local function frecency_enabled()
  local e = os.getenv('LUSTY_FRECENCY')
  if e ~= nil and e ~= '' then
    return e == '1' or e == 'true'
  end
  local gv = vim.g.LustyExplorerFrecency
  if gv == nil then
    return true
  end
  if type(gv) == 'boolean' then
    return gv
  end
  if type(gv) == 'number' then
    return gv ~= 0
  end
  return not (gv == '0' or gv == 'false')
end

--- g:LustyExplorerFollowMountPoints = 1 lets the deep walk enter mount points
--- (the deep search never crosses them by default).
local function follow_mounts_enabled()
  local v = vim.g.LustyExplorerFollowMountPoints
  return v == 1 or v == true or v == '1'
end

--- g:LustyExplorerAlwaysShowDotFiles = 1 keeps dotfiles visible from the start
--- (without it the query has to begin with '.').
local function always_dots_enabled()
  local v = vim.g.LustyExplorerAlwaysShowDotFiles
  return v == 1 or v == true or v == '1'
end

local function icon_for(item)
  if item.kind == 'd' then
    return icons.dir
  end
  if item.kind == 'l' then
    return icons.link
  end
  local low = basename(item.label):lower()
  for _, pair in ipairs(icons.ext) do
    if low:sub(-#pair[1]) == pair[1] then
      return pair[2]
    end
  end
  return icons.file
end

local Picker = {}
Picker.__index = Picker

function Picker.new(root, depth)
  local self = setmetatable({}, Picker)
  self.root = root
  self.query = ''
  self.selected = 0 -- ranked position
  self.offset = 0 -- top visible ranked position
  self.total = 0
  self.window = {} -- ranked pos (offset+1..) -> { i, kind, label, path }
  self.handlers = {} -- FIFO of response handlers; serve answers in order
  self.outbuf = {}
  self.dirs = nil -- cached top-level dir names for '/' completion
  self.show_dots = always_dots_enabled() -- g:LustyExplorerAlwaysShowDotFiles
  self.always_dots = self.show_dots
  self.maxw = 12 -- widest label (chars) in the current ranked set
  self.closed = false
  self.long = false -- long view: metadata columns via serve M (C-l toggles)
  self.icons = icons_enabled() -- nerd-font grid icons (LUSTY_ICONS / g:LustyExplorerIcons)
  self.dirs_first = dirs_first_enabled() -- dirs grouped first in name order (LUSTY_DIRS_FIRST / g:LustyExplorerDirsFirst)
  self.reverse = reverse_enabled() -- reverse each depth group (LUSTY_REVERSE / g:LustyExplorerReverse)
  self.sort = 0 -- listing order: 0 name, 1 ext, 2 size, 3 time (C-y cycles)
  -- Search depth: g:LustyExplorerSearchDepth is only the starting value; C-d
  -- cycles it at runtime and the new value survives navigation (restart).
  self.depth = depth or tonumber(vim.g.LustyExplorerSearchDepth) or 2
  self.marked = {} -- path -> true: files picked with C-Space (multi-select)
  self.mark_order = {} -- marked paths in pick order (open order)
  self.caps = {} -- backend capabilities from the `X <names>` line (e.g. preview)
  self.preview_on = false -- C-r toggles the preview pane
  self.preview_win = nil
  self.preview_buf = nil
  self.preview_key = nil -- path|w|h cache key of the rendered pane
  self.preview_lines = nil -- { dim = bool, lines = { ... } }
  self.loading = true -- first serve listing not yet received (avoid a wrong [0])
  self.orig_win = api.nvim_get_current_win()
  self._timer = nil
  return self
end

function Picker:width()
  local envw = tonumber(os.getenv('LUSTY_WIDTH'))
  if envw and envw >= 60 then
    return math.max(60, math.min(envw, vim.o.columns - 4))
  end
  local ratio = tonumber(vim.g.LustyExplorerWidthRatio) or 0.8
  ratio = math.max(0.5, math.min(0.98, ratio))
  return math.max(60, math.floor(vim.o.columns * ratio))
end

function Picker:height()
  local envr = tonumber(os.getenv('LUSTY_ROWS'))
  if envr and envr >= 4 then
    -- Total box height including the two rounded-border rows, matching the
    -- standalone `--rows`; the window itself is two rows shorter.
    return math.max(2, math.min(envr - 2, vim.o.lines - 2))
  end
  -- 8 rows in total on screen: the rounded border takes two, the window holds
  -- five entry rows plus the prompt.
  return math.min(6, math.max(1, vim.o.lines - 2))
end

function Picker:list_rows()
  -- Entry rows inside the window: everything but the prompt line, so the grid
  -- fills the window instead of leaving its last row empty.
  return math.max(1, self:height() - 1)
end

--- Max columns of the entry grid: choose a pitch that fits the float width
--- exactly (col_w + 2 separator), so rows never overflow or wrap.
function Picker:max_cols()
  if self.long then
    return 1
  end
  local w = self:width()
  local rows = self:list_rows()
  local total = math.max(self.total, 1)
  local needed = math.max(1, math.ceil(total / rows))
  -- cap the width influence: one huge name must not force a single column
  local name_w = math.max(math.min(self.maxw or 12, 20), 1)
  if self.icons then
    name_w = name_w + 2 -- icon glyph + trailing space occupy two display cells
  end
  local byw = math.max(1, math.floor((w + 2) / (name_w + 4)))
  local cols = math.min(needed, byw, 8)
  return math.max(1, cols)
end

function Picker:col_width()
  local cols = self:max_cols()
  local w = self:width()
  -- remaining width for the text columns after the separators
  local text_w = w - 2 * (cols - 1)
  return math.max(6, math.floor(text_w / cols))
end

--- Long-view column mask: LUSTY_COLUMNS wins over g:LustyExplorerColumns;
--- unknown tokens are ignored, an empty result means all fields
--- (perm,user,size,time). CLI flags do not apply to the nvim float.
function Picker:meta_mask()
  local spec = os.getenv('LUSTY_COLUMNS')
  if spec == nil or spec == '' then
    spec = vim.g.LustyExplorerColumns
  end
  if type(spec) ~= 'string' or spec == '' then
    return 15
  end
  local mask = 0
  for tok in spec:gmatch('[^,]+') do
    local t = tok:match('^%s*(.-)%s*$') or ''
    if t == 'perm' then
      mask = mask + 1
    elseif t == 'user' then
      mask = mask + 2
    elseif t == 'size' then
      mask = mask + 4
    elseif t == 'time' then
      mask = mask + 8
    end
  end
  if mask == 0 then
    return 15
  end
  return mask
end

--- Fetch eza-style metadata for the visible rows only (serve request M:
--- mask first, then entry indices). The backend answers one "K <i> <meta>"
--- line per index; meta lines attach to the matching window row, then the
--- float is redrawn. Skipped while another request is in flight; the draw
--- that follows that response re-runs ensure_meta if rows are still missing.
function Picker:ensure_meta()
  if not self.long or #self.handlers > 0 then
    return
  end
  local mask = self:meta_mask()
  if mask == 0 then
    return
  end
  local seen = {}
  local idx = {}
  for _, item in ipairs(self.window) do
    if item.meta == nil and not seen[item.i] then
      seen[item.i] = true
      idx[#idx + 1] = tostring(item.i)
    end
  end
  if #idx == 0 then
    return
  end
  local self_ref = self
  local parts = { 'M', tostring(mask) }
  for _, i in ipairs(idx) do
    parts[#parts + 1] = i
  end
  self:request(parts, function(lines)
    for _, ln in ipairs(lines) do
      local i, meta = ln:match('^K (%d+) ?(.*)$')
      if i then
        i = tonumber(i)
        for _, item in ipairs(self_ref.window) do
          if item.i == i then
            item.meta = meta
            break
          end
        end
      end
    end
    vim.schedule(function()
      self_ref:draw()
    end)
  end)
end

--- Number of positions covered by one screenful of the grid.
function Picker:screen_count()
  return self:list_rows() * self:max_cols()
end

--- Preview pane width: LUSTY_PREVIEW_WIDTH / g:LustyExplorerPreviewWidth,
--- else ~35% of the editor, clamped so the picker still fits beside it.
function Picker:preview_width()
  local w = tonumber(os.getenv('LUSTY_PREVIEW_WIDTH')) or tonumber(vim.g.LustyExplorerPreviewWidth)
  if not w or w < 8 then
    w = math.max(24, math.floor(vim.o.columns * 0.35))
  end
  return math.max(8, math.min(w, vim.o.columns - 20))
end

--- Open the preview float to the right of the picker (focus stays on the
--- picker). Geometry is fixed at open time; reopen on C-r to resize.
function Picker:open_preview()
  local w = self:preview_width()
  local ph = self:height()
  local row = math.max(0, vim.o.lines - ph - 1)
  local picker_col = math.max(0, math.floor((vim.o.columns - self:width()) / 2))
  local col = math.min(vim.o.columns - w - 1, picker_col + self:width() + 1)
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, false, {
    relative = 'editor',
    width = w,
    height = ph,
    row = row,
    col = math.max(0, col),
    style = 'minimal',
    border = 'rounded',
  })
  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'modifiable', true)
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  api.nvim_win_set_option(win, 'wrap', false)
  api.nvim_win_set_option(win, 'winhighlight', 'Normal:LustyNativeFloat,FloatBorder:LustyNativeBorder')
  self.preview_buf = buf
  self.preview_win = win
  self.preview_key = nil
  self.preview_lines = nil
end

function Picker:close_preview()
  if self.preview_win and api.nvim_win_is_valid(self.preview_win) then
    pcall(api.nvim_win_close, self.preview_win, true)
  end
  if self.preview_buf and api.nvim_buf_is_valid(self.preview_buf) then
    pcall(api.nvim_buf_delete, self.preview_buf, { force = true })
  end
  self.preview_win = nil
  self.preview_buf = nil
  self.preview_key = nil
  self.preview_lines = nil
end

function Picker:toggle_preview()
  if not self.caps.preview then
    vim.notify('lusty: this backend has no preview (no X preview)', vim.log.levels.WARN)
    return
  end
  self.preview_on = not self.preview_on
  if self.preview_on then
    self:open_preview()
    self:refresh_preview()
  else
    self:close_preview()
  end
end

--- Request the preview for the selected row; the (path, width, height) key
--- skips re-requesting when nothing changed (e.g. plain redraws).
function Picker:refresh_preview()
  if not self.preview_on or not self.preview_buf or not api.nvim_buf_is_valid(self.preview_buf) then
    return
  end
  local item = self.window[self.selected - self.offset + 1]
  if not item then
    if self.preview_key ~= 'none' then
      self.preview_key = 'none'
      self.preview_lines = { dim = true, lines = { '(no selection)' } }
      self:render_preview()
    end
    return
  end
  local w = api.nvim_win_get_width(self.preview_win)
  local h = api.nvim_win_get_height(self.preview_win)
  local key = item.path .. '|' .. w .. '|' .. h
  if key == self.preview_key then
    return
  end
  self.preview_key = key
  self:request({ 'V', tostring(item.i), tostring(w), tostring(h) }, function(lines)
    local dim = true
    local body = {}
    for _, ln in ipairs(lines) do
      local n, d = ln:match('^V (%d+) ([01])$')
      if n then
        dim = d == '1'
      else
        local text = ln:match('^L ?(.*)$')
        if text then
          body[#body + 1] = text
        end
      end
    end
    self.preview_lines = { dim = dim, lines = body }
    vim.schedule(function()
      self:render_preview()
    end)
  end)
end

--- Paint the last preview response into the pane buffer. Rows carrying SGR
--- (chafa art) become colour extmarks; colourless rows are dimmed like before.
function Picker:render_preview()
  if not self.preview_on or not self.preview_buf or not api.nvim_buf_is_valid(self.preview_buf) then
    return
  end
  local data = (self.preview_lines and self.preview_lines.lines) or {}
  local rows, all_runs = {}, {}
  for i = 1, #data do
    rows[i], all_runs[i] = parse_sgr(data[i])
  end
  api.nvim_buf_set_lines(self.preview_buf, 0, -1, false, rows)
  api.nvim_buf_clear_namespace(self.preview_buf, preview_ns, 0, -1)
  for i = 1, #rows do
    local runs = all_runs[i]
    if #runs == 0 then
      if #rows[i] > 0 then
        api.nvim_buf_add_highlight(self.preview_buf, preview_ns, 'LustyNativeMeta', i - 1, 0, -1)
      end
    else
      for _, r in ipairs(runs) do
        if r[3] then
          api.nvim_buf_add_highlight(
            self.preview_buf,
            preview_ns,
            preview_color('fg', r[3]),
            i - 1,
            r[1],
            r[2]
          )
        end
        if r[4] then
          api.nvim_buf_add_highlight(
            self.preview_buf,
            preview_ns,
            preview_color('bg', r[4]),
            i - 1,
            r[1],
            r[2]
          )
        end
      end
    end
  end
end

function Picker:open_window()
  local w, h = self:width(), self:height()
  -- bottom orientation (original Lusty gravity): anchored just above the
  -- statusline, horizontally centered
  local row = math.max(0, vim.o.lines - h - 1)
  local col = math.max(0, math.floor((vim.o.columns - w) / 2))
  local buf = api.nvim_create_buf(false, true)
  local win = api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = w,
    height = h,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })
  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'modifiable', true)
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  api.nvim_win_set_option(win, 'wrap', false)
  api.nvim_win_set_option(win, 'winhighlight', 'Normal:LustyNativeFloat,FloatBorder:LustyNativeBorder')
  api.nvim_win_set_option(win, 'winblend', 0)
  api.nvim_buf_set_lines(buf, 0, -1, false, {})
  self.buf = buf
  self.win = win
  self:setup_keymaps()
  -- Modal picker: if focus ever leaves the float (e.g. a click on the
  -- underlying buffer), pull it straight back. Otherwise letters typed
  -- outside land in the original buffer, where 'c' starts the change
  -- operator and nvim waits a timeoutlen for a motion.
  local self_ref = self
  self.leave_grp = api.nvim_create_augroup('LustyPickFocus' .. buf, { clear = true })
  api.nvim_create_autocmd('BufLeave', {
    group = self.leave_grp,
    buffer = buf,
    callback = function()
      if not self_ref.closed and api.nvim_win_is_valid(self_ref.win) then
        vim.schedule(function()
          if not self_ref.closed and api.nvim_win_is_valid(self_ref.win) then
            api.nvim_set_current_win(self_ref.win)
          end
        end)
      end
    end,
  })
end

function Picker:setup_keymaps()
  local buf = self.buf
  local self_ref = self
  local function map(lhs, action)
    local opts = { nowait = true, silent = true, noremap = true }
    opts.callback = function()
      self_ref:handle(action)
    end
    api.nvim_buf_set_keymap(buf, 'n', lhs, '', opts)
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
    map(lhs, ch)
  end
  for ru, en in pairs(RU2EN) do
    map(ru, en)
  end
  map('<Tab>', 'enter')
  map('<CR>', 'enter')
  map('<S-CR>', 'enter')
  map('<BS>', 'backspace')
  map('<C-h>', 'backspace')
  map('<C-w>', 'updir')
  map('<C-n>', 'down')
  map('<C-j>', 'down')
  map('<C-p>', 'up')
  map('<C-k>', 'up')
  map('<Down>', 'down')
  map('<Up>', 'up')
  map('<C-f>', 'colnext')
  map('<Right>', 'colnext')
  map('<C-b>', 'colprev')
  map('<Left>', 'colprev')
  map('<PageDown>', 'pagedown')
  map('<PageUp>', 'pageup')
  map('<Home>', 'first')
  map('<C-a>', 'first')
  map('<End>', 'last')
  -- C-e: open the typed text as a new buffer (Lua-port parity; parent dirs are
  -- created). C-d: cycle the search depth 1..6 at runtime (buffers/grep use C-d
  -- for delete instead; this is the filesystem float).
  map('<C-e>', 'create')
  map('<C-d>', 'cycle_depth')
  map('<C-u>', 'clear')
  map('<C-Space>', 'mark')
  -- C-y: sort cycle (C-s collides with terminal/kitty flow control)
  map('<C-y>', 'cycle_sort')
  map('<C-t>', 'open_tab')
  map('<C-o>', 'open_split')
  map('<C-v>', 'open_vsplit')
  map('<C-l>', 'toggle_long')
  -- C-r: preview pane (only when the backend advertises `X preview`).
  map('<C-r>', 'toggle_preview')
  map('<Esc>', 'cancel')
  map('<C-c>', 'cancel')
  map('<C-g>', 'cancel')
end

function Picker:request(parts, handler)
  if #self.handlers == 0 then
    self.outbuf = {}
  end
  self.handlers[#self.handlers + 1] = handler
  vim.fn.chansend(self.job, table.concat(parts, '\t') .. '\n')
end

--- Ship the frecency journal once, before the first Q, as fire-and-forget
--- `F <score> <path>` records. The backend then leads the empty query with the
--- paths the user opens most; an old backend simply ignores the unknown lines.
function Picker:send_frecency()
  if not frecency_enabled() then
    return
  end
  local records = {}
  for _, path in ipairs(frecency.paths()) do
    local score = frecency.score(path)
    if score and score > 0 then
      records[#records + 1] = 'F\t' .. string.format('%.6f', score) .. '\t' .. escape(path)
    end
  end
  if #records > 0 then
    vim.fn.chansend(self.job, table.concat(records, '\n') .. '\n')
  end
end

function Picker:rerank()
  pf('rerank')
  local from = self.offset
  local to = self.offset + self:screen_count()
  self:request({
    'Q',
    tostring(from),
    tostring(to),
    self.query,
    tostring(self.sort),
    self.dirs_first and '1' or '0',
    self.reverse and '1' or '0',
  }, function(lines)
    local win_rows = {}
    local total = self.total
    for _, ln in ipairs(lines) do
      local n = ln:match('^N (%d+)$')
      if n then
        total = tonumber(n)
      else
        local wm = ln:match('^W (%d+)$')
        if wm then
          self.maxw = tonumber(wm)
        else

        local i, kind, label, path = ln:match('^R (%d+) (%a) ([^\t]+)\t(.*)$')
        if i then
          win_rows[#win_rows + 1] = {
            i = tonumber(i),
            kind = kind,
            -- Display label: control escapes stay visible (see unescape).
            label = unescape(label, true),
            -- Open path: exact bytes, non-UTF8 included.
            path = unescape(path),
          }
        end
        end
      end
    end
    self.total = total
    if self.selected > self.total - 1 and self.total > 0 then
      self.selected = self.total - 1
    end
    self.window = win_rows
    self.loading = false
    -- The first Q cannot know `total` yet, so max_cols() guesses a single
    -- column and the page covers only list_rows() entries; with the total in
    -- hand the grid may want more columns and the fetched page is too short
    -- to fill it. Re-ask once for the full page instead of leaving the extra
    -- rows empty.
    local want = math.min(self.total, self:screen_count())
    if #win_rows < want and to < want then
      self:rerank()
      return
    end
    vim.schedule(function()
      self:draw()
      self:refresh_preview()
    end)
  end)
end

function Picker:draw()
  if self.closed or not api.nvim_buf_is_valid(self.buf) then
    return
  end
  pf('draw')
  if self.loading then
    -- First listing is still in flight from the serve backend: show a plain
    -- box with a dim ellipsis and the path prompt (no [N] counter, no stale
    -- grid) instead of flashing a wrong 0 total.
    local w = self:width()
    local rows = self:list_rows()
    local lines = {}
    for r = 1, rows do
      lines[r] = string.rep(' ', w)
    end
    lines[1] = '…' .. string.rep(' ', math.max(0, w - 1))
    lines[rows + 1] = self:prompt_text()
    api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
    api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeMeta', 0, 0, 1)
    self:paint_prompt(rows + 1)
    return
  end
  local rows = self:list_rows()
  local cols = self:max_cols()
  local h = rows + 1 -- grid rows + one prompt line
  local col_w = self:col_width()
  local lines = {}
  local cells = {} -- { line, col, item, pos }
  if self.long then
    -- long view: one entry per line; serve already supplied the metadata
    -- (item.meta, eza -l style). Metadata is ascii, so byte length == width.
    local w = self:width()
    for r = 1, rows do
      local pos = self.offset + (r - 1)
      local item = self.window[pos - self.offset + 1]
      if item then
        local meta = item.meta or ''
        local prefix = ''
        if meta ~= '' then
          prefix = meta .. ' '
        end
        local icon_pre = ''
        local name = item.label
        if self.icons then
          icon_pre = icon_for(item) .. ' '
          name = icon_pre .. name
        elseif item.kind == 'd' then
          name = name .. '/'
        end
        local pw = #prefix
        local maxw = math.max(4, w - pw)
        local text = name
        local nw = vim.fn.strdisplaywidth(text)
        if nw > maxw then
          local nchars = vim.fn.strchars(text)
          while nw > maxw and nchars > 0 do
            nchars = nchars - 1
            text = vim.fn.strcharpart(text, 0, nchars)
            nw = vim.fn.strdisplaywidth(text)
          end
        end
        local full = prefix .. text
        full = full .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(full)))
        lines[r] = full
        cells[#cells + 1] = {
          line = r,
          col = 1,
          item = item,
          pos = pos,
          icon_bytes = #icon_pre,
          name_start = pw,
          name_bytes = #text,
          meta = meta,
          long = true,
        }
      end
    end
  else
    for r = 1, rows do
      local bufparts = {}
      local byte_start = 0 -- byte offset of the current cell within lines[r]
      for c = 1, cols do
        -- row-major: fill left-to-right, then next row (original Lusty order)
        local pos = self.offset + (r - 1) * cols + (c - 1)
        local item = self.window[pos - self.offset + 1]
        if item then
          local icon_pre = ''
          local label = item.label
          if self.icons then
            icon_pre = icon_for(item) .. ' '
            label = icon_pre .. label
          elseif item.kind == 'd' then
            label = label .. '/'
          end
          -- pad to the full column width (display cells) so columns align;
          -- truncated cells are padded too, otherwise that row shifts by one
          -- and the selection highlight (fixed pitch) lands off.
          local text = label
          local w = vim.fn.strdisplaywidth(text)
          if w > col_w - 1 then
            local nchars = vim.fn.strchars(text)
            while w > col_w - 1 and nchars > 0 do
              nchars = nchars - 1
              text = vim.fn.strcharpart(text, 0, nchars)
              w = vim.fn.strdisplaywidth(text)
            end
          end
          local text_bytes = #text
          text = text .. string.rep(' ', math.max(0, col_w - w))
          bufparts[c] = text
          cells[#cells + 1] = {
            line = r,
            col = c,
            item = item,
            pos = pos,
            byte_start = byte_start,
            text_bytes = text_bytes,
            cell_bytes = #text,
            icon_bytes = #icon_pre,
          }
          byte_start = byte_start + #text + 2
        end
      end
      lines[r] = table.concat(bufparts, '  ')
    end
  end
  for i = 1, h do
    if not lines[i] then
      lines[i] = ''
    end
  end
  lines[h] = self:prompt_text()
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  for _, cell in ipairs(cells) do
    local entry = {
      name = basename(cell.item.label),
      is_dir = cell.item.kind == 'd',
      is_link = cell.item.kind == 'l',
      path = cell.item.path,
    }
    local group = lsc.group_for(entry)
    local name_from
    local name_to
    if cell.long then
      name_from = cell.name_start
      name_to = cell.name_start + cell.name_bytes
    else
      name_from = cell.byte_start
      name_to = cell.byte_start + cell.text_bytes
    end
    if cell.long and cell.meta ~= '' and cell.pos ~= self.selected then
      api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeMeta', cell.line - 1, 0, #cell.meta)
    end
    if group then
      api.nvim_buf_add_highlight(self.buf, ns, group, cell.line - 1, name_from, name_to)
    end
    -- approximate fuzzy-match highlight: underline the first plain
    -- case-insensitive occurrence of the query in the entry basename
    -- Underline the matched query letters in every cell, including the
    -- selected one, so the match survives the selection bar.
    local q = self.query
    if q ~= '' and q:sub(1, 1) ~= '.' then
      local base = basename(cell.item.label)
      local s, e = base:lower():find(q:lower(), 1, true)
      if s and e then
        local name_start = name_from + (cell.icon_bytes or 0)
        local lstart = #cell.item.label - #base
        api.nvim_buf_add_highlight(
          self.buf, ns, 'LustyNativeMatch', cell.line - 1,
          name_start + lstart + s - 1, name_start + lstart + e
        )
      end
    end
    -- Marked file (C-Space): a distinct tint over the whole name, drawn after
    -- the match underline so it wins; the selection bar is painted later on top.
    if self.marked[cell.item.path] then
      api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeMark', cell.line - 1, name_from, name_to)
    end
  end
  if self.total > 0 and rows > 0 then
    local sel_row
    local sel_from = 0
    local sel_to = 0
    if self.long then
      sel_row = self.selected - self.offset
      if sel_row >= 0 and sel_row < rows then
        local line = lines[sel_row + 1] or ''
        sel_from = 0
        sel_to = math.max(1, #line)
      end
    else
      sel_row = math.floor(self.selected / cols)
      for _, cell in ipairs(cells) do
        if cell.pos == self.selected then
          sel_from = cell.byte_start
          sel_to = cell.byte_start + cell.cell_bytes
          break
        end
      end
    end
    if sel_row >= 0 and sel_row < rows then
      api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', sel_row, sel_from, sel_to)
    end
  end
  self:paint_prompt(h)
  pf('drawn')
  self:ensure_meta()
end

--- Bottom prompt: current path with Lusty prompt colors, then > query.
function Picker:prompt_text()
  local path = self.root
  local home = os.getenv('HOME') or ''
  if home ~= '' and path:sub(1, #home) == home then
    path = '~' .. path:sub(#home + 1)
  end
  local tail = path .. ' \u{f105} ' .. self.query
  if self.icons then
    tail = ICON_DIR .. ' ' .. tail
  end
  if self.total > 0 then
    tail = tail .. ' [' .. self.total .. ']'
  end
  if self.sort > 0 then
    tail = tail .. ' <' .. SORT_LABELS[self.sort + 1] .. '>'
  end
  if #self.mark_order > 0 then
    tail = tail .. ' (' .. #self.mark_order .. ' marked)'
  end
  tail = tail .. '  d' .. tostring(self.depth)
  return tail
end

function Picker:paint_prompt(h)
  local line = h - 1
  local home = os.getenv('HOME') or ''
  local segs = {} -- {start, len, group}
  local col = 0
  local function add(text, group)
    if text and #text > 0 then
      segs[#segs + 1] = { col, #text, group }
      col = col + #text
    end
  end
  if self.icons then
    add(ICON_DIR .. ' ', 'LustyPromptSep')
  end
  local path = self.root
  if home ~= '' and path:sub(1, #home) == home then
    add('~', 'LustyPromptTilde')
    path = path:sub(#home + 1)
  elseif path:sub(1, 1) ~= '/' then
    -- relative root: show as-is in path color
  end
  local seg = ''
  for i = 1, #path do
    local ch = path:sub(i, i)
    if ch == '/' then
      add(seg, 'LustyPromptPath')
      add('/', 'LustyPromptSep')
      seg = ''
    else
      seg = seg .. ch
    end
  end
  add(seg, 'LustyPromptPath')
  add(' ', 'LustyPromptSep')
  add('\u{f105}', 'LustyPromptSep')
  add(' ', 'LustyPromptQuery')
  add(self.query, 'LustyPromptQuery')
  if self.total > 0 then
    add(' [' .. self.total .. ']', 'LustyPromptPath')
  end
  if self.sort > 0 then
    add(' <' .. SORT_LABELS[self.sort + 1] .. '>', 'LustyPromptPath')
  end
  if #self.mark_order > 0 then
    add(' (' .. #self.mark_order .. ' marked)', 'LustyPromptPath')
  end
  -- Search depth (C-d cycles it), dimmed; must stay in sync with prompt_text.
  add('  d' .. tostring(self.depth), 'LustyNativeMeta')
  for _, seg2 in ipairs(segs) do
    if seg2[3] then
      api.nvim_buf_add_highlight(self.buf, ns, seg2[3], line, seg2[1], seg2[1] + seg2[2])
    end
  end
end

function Picker:ensure_visible()
  local screen = self:screen_count()
  if self.selected < self.offset then
    self.offset = math.max(0, math.floor(self.selected / screen) * screen)
  elseif self.selected >= self.offset + screen then
    self.offset = math.floor(self.selected / screen) * screen
  end
end

--- Move one grid column left/right (wrap), mirroring the Lua port.
function Picker:column_nav(delta)
  local rows = self:list_rows()
  if self.total == 0 or rows == 0 then
    self.selected = 0
    return
  end
  local columns = math.ceil(self.total / rows)
  local cur_col = math.floor(self.selected / rows)
  local cur_row = self.selected % rows
  local new_col = (cur_col + delta) % columns
  if (new_col + 1) * (cur_row + 1) > self.total then
    new_col = delta > 0 and 0 or math.max(0, columns - 2)
  end
  local sel = new_col * rows + cur_row
  if sel >= self.total then
    sel = self.total - 1
  end
  self.selected = sel
  self:ensure_visible()
  self:rerank()
end

--- Debounce for typing-triggered reranks; 0 (or g:LustyExplorerInputDebounce = 0)
--- reranks synchronously like before.
function Picker:debounce_ms()
  local v = vim.g.LustyExplorerInputDebounce
  if type(v) == 'number' then
    return math.max(0, v)
  end
  v = tonumber(v)
  if v then
    return math.max(0, v)
  end
  return 20
end

--- Rerank after a short quiet period so fast typing on huge listings only
--- issues one request; navigation reranks immediately.
function Picker:schedule_rerank()
  local ms = self:debounce_ms()
  if ms <= 0 then
    self:rerank()
    return
  end
  if self._timer then
    self._timer:stop()
  end
  local self_ref = self
  self._timer = vim.uv.new_timer()
  self._timer:start(ms, 0, function()
    vim.schedule(function()
      if self_ref._timer then
        self_ref._timer:stop()
        self_ref._timer = nil
      end
      if not self_ref.closed then
        pf('fire')
        self_ref:rerank()
      end
    end)
  end)
end

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.leave_grp then
    pcall(api.nvim_del_augroup_by_name, self.leave_grp)
    self.leave_grp = nil
  end
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
  end
  self:close_preview()
  -- close the float window itself first: deleting the buffer of a shown
  -- window can leave an empty floating shell behind
  if self.win and api.nvim_win_is_valid(self.win) then
    pcall(api.nvim_win_close, self.win, true)
  end
  if self.buf and api.nvim_buf_is_valid(self.buf) then
    pcall(api.nvim_buf_delete, self.buf, { force = true })
  end
  if api.nvim_win_is_valid(self.orig_win) then
    pcall(api.nvim_set_current_win, self.orig_win)
  end
end

function Picker:handle(action)
  if self.closed then
    return
  end
  pf('key:' .. tostring(action))
  if action == 'cancel' then
    self:close()
    return
  end
  if action == 'mark' then
    -- Multi-select: C-Space toggles the file under the cursor. Directories are
    -- not markable (Enter on a directory re-roots the picker anyway).
    local item = self.window[self.selected - self.offset + 1]
    if item and item.kind ~= 'd' then
      local path = item.path
      if self.marked[path] then
        self.marked[path] = nil
        for i, p in ipairs(self.mark_order) do
          if p == path then
            table.remove(self.mark_order, i)
            break
          end
        end
      else
        self.marked[path] = true
        self.mark_order[#self.mark_order + 1] = path
      end
      self:draw()
    end
    return
  end
  if action == 'create' then
    self:create_file()
    return
  end
  if action == 'cycle_depth' then
    self:cycle_depth()
    return
  end
  if action == 'toggle_preview' then
    self:toggle_preview()
    return
  end
  if action == 'toggle_long' then
    self.long = not self.long
    -- realign the page to the new geometry (grid rows*cols vs long rows)
    local screen = self:screen_count()
    if self.total > 0 and screen > 0 then
      self.offset = math.max(0, math.floor(self.selected / screen) * screen)
    end
    self:rerank()
    return
  end
  if action == 'cycle_sort' then
    self.sort = (self.sort + 1) % #SORT_LABELS
    -- the order changed, so restart from the top of the listing
    self.selected = 0
    self.offset = 0
    self:rerank()
    return
  end
  if action == 'down' then
    if self.total > 0 then
      self.selected = (self.selected + 1) % self.total
      self:ensure_visible()
      self:rerank()
    end
    return
  end
  if action == 'up' then
    if self.total > 0 then
      self.selected = (self.selected - 1) % self.total
      self:ensure_visible()
      self:rerank()
    end
    return
  end
  if action == 'colnext' or action == 'colprev' then
    self:column_nav(action == 'colnext' and 1 or -1)
    return
  end
  if action == 'pagedown' or action == 'pageup' then
    local screen = self:screen_count()
    local delta = action == 'pagedown' and screen or -screen
    if self.total > 0 then
      self.selected = math.max(0, math.min(self.selected + delta, self.total - 1))
      self:ensure_visible()
      self:rerank()
    end
    return
  end
  if action == 'first' or action == 'last' then
    if self.total > 0 then
      self.selected = action == 'first' and 0 or (self.total - 1)
      self:ensure_visible()
      self:rerank()
    end
    return
  end
  if action == 'clear' then
    if #self.query > 0 then
      self.query = ''
      self.selected = 0
      self.offset = 0
      if self:maybe_toggle_dots() then
        return
      end
      self:schedule_rerank()
    end
    return
  end
  if action == 'backspace' then
    if #self.query > 0 then
      self.query = self.query:sub(1, -2)
      self.selected = 0
      self.offset = 0
      if self:maybe_toggle_dots() then
        return
      end
      self:schedule_rerank()
    end
    return
  end
  if action == 'updir' then
    if #self.query > 0 then
      -- first C-w clears the typed text (shell/vim word-delete feel)
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:schedule_rerank()
      return
    end
    local parent = self.root:gsub('/[^/]+$', '')
    if parent == '' then
      parent = '/'
    end
    if parent ~= self.root then
      self:restart(parent)
    end
    return
  end
  if action == 'enter' or action == 'open_tab' or action == 'open_split' or action == 'open_vsplit' then
    self:open_current(action)
    return
  end
  -- typing: action is a character
  local ch = action
  if ch == '/' then
    self:slash_enter()
    return
  end
  if #ch == 1 then
    self.query = self.query .. ch
    self.selected = 0
    self.offset = 0
    if self:maybe_toggle_dots() then
      return
    end
    self:schedule_rerank()
  end
end

--- Query starting with '.' reveals dotfiles: restart the backend with
--- --dots when the mode changes (returns true when it did).
function Picker:maybe_toggle_dots()
  local want = self.query:sub(1, 1) == '.' or self.always_dots
  if want ~= self.show_dots then
    self.show_dots = want
    self.window = {}
    self:start_backend() -- reranks internally
    return true
  end
  return false
end

--- '/' descends into a directory when the typed prefix uniquely names one
--- (exact name or unique prefix), shell style.
function Picker:slash_enter()
  local q = self.query
  if q == '' then
    -- a lone '/' moves to the filesystem root, Lusty style
    if self.root ~= '/' then
      self:restart('/')
    end
    return
  end
  if self.dirs == nil then
    self:request({ 'D' }, function(lines)
      local dirs = {}
      for _, ln in ipairs(lines) do
        local name = ln:match('^D (.+)$')
        if name then
          dirs[#dirs + 1] = unescape(name)
        end
      end
      self.dirs = dirs
      self:complete_slash(q)
    end)
    return
  end
  self:complete_slash(q)
end

function Picker:complete_slash(q)
  local ql = q:lower()
  local candidates = {}
  for _, d in ipairs(self.dirs or {}) do
    if d:lower() == ql or d:lower():sub(1, #ql) == ql then
      candidates[#candidates + 1] = d
    end
  end
  if #candidates == 1 then
    local path = self.root == '/' and '/' .. candidates[1] or self.root .. '/' .. candidates[1]
    self:restart(path)
    return
  end
  -- not a unique directory: let '/' be typed as an ordinary character
  self.query = q .. '/'
  self.selected = 0
  self.offset = 0
  self:rerank()
end

function Picker:restart(root, depth)
  self:close() -- restores the caller window
  local np = Picker.new(root, depth or self.depth)
  np:startup()
  return np
end

--- C-d: bump the search depth 1..6 and re-list in place, keeping the query.
function Picker:cycle_depth()
  self.depth = self.depth % 6 + 1
  local query = self.query
  local np = self:restart(self.root, self.depth)
  if query ~= '' then
    np.query = query
    np:rerank()
  end
  return np
end

--- C-e: treat the typed text as a path and open it as a buffer, creating the
--- parent directories first; the file itself appears on :w (Lua-port parity).
function Picker:create_file()
  local name = self.query
  if name == '' then
    vim.notify('lusty: type a file name first (C-e creates it)', vim.log.levels.WARN)
    return
  end
  local path = name
  if path:sub(1, 1) ~= '/' and path:sub(1, 1) ~= '~' then
    path = self.root .. '/' .. path
  end
  path = vim.fn.expand(path)
  local dir = vim.fn.fnamemodify(path, ':h')
  if dir ~= '' and vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, 'p')
  end
  local win = api.nvim_get_current_win()
  self:close()
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_current_win, win)
  end
  vim.cmd('edit ' .. vim.fn.fnameescape(path))
end

function Picker:open_current(action)
  local rel = self.selected - self.offset
  local item = self.window[rel + 1]
  if not item then
    return
  end
  if item.kind == 'd' then
    -- Entering a directory is a visit too: record it so the dirs MRU
    -- (,. then C-r) reflects where the filesystem float was used.
    frecency.record(item.path)
    self:restart(item.path)
    return
  end
  local cmds = { edit = 'edit', open_tab = 'tabedit', open_split = 'split', open_vsplit = 'vsplit' }
  local ex = action == 'enter' and 'edit' or cmds[action]
  if not ex then
    return
  end
  -- Multi-select: with marks open every marked file (plus the cursor if it is
  -- unmarked); without marks just the selection. `edit` loads the first and
  -- adds the rest as buffers, so "open several" does not silently replace.
  local paths = {}
  if #self.mark_order > 0 then
    for _, p in ipairs(self.mark_order) do
      paths[#paths + 1] = p
    end
    if not self.marked[item.path] then
      paths[#paths + 1] = item.path
    end
  else
    paths[1] = item.path
  end
  local win = api.nvim_get_current_win()
  self:close()
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_current_win, win)
  end
  for i, path in ipairs(paths) do
    -- Record the jump in the lusty frecency journal so the recent explorer
    -- (",.") reflects opens made from the filesystem picker too.
    frecency.record(path)
    if ex == 'edit' and i > 1 then
      vim.cmd('badd ' .. vim.fn.fnameescape(path))
    else
      vim.cmd(ex .. ' ' .. vim.fn.fnameescape(path))
    end
  end
end

function Picker:startup()
  if vim.fn.executable('lusty') ~= 1 then
    vim.notify('lusty binary not found on PATH', vim.log.levels.ERROR)
    return
  end
  self:open_window()
  self:start_backend()
end

function Picker:start_backend()
  local depth = self.depth
  local skip = vim.g.LustyExplorerSkipDirs
  if skip == nil or skip == '' then
    skip = 'pic,tmp'
  end
  local cmd = { 'lusty', 'serve', self.root, '--depth', tostring(depth), '--skip', skip }
  if self.show_dots then
    cmd[#cmd + 1] = '--dots'
  end
  if follow_mounts_enabled() then
    cmd[#cmd + 1] = '--follow-mounts'
  end
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
  end
  local self_ref = self
  local acc = ''
  local errbuf = ''
  self.caps = {}
  self.job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if self_ref.closed then
        return
      end
      acc = acc .. table.concat(data, '\n')
      while true do
        local nl = acc:find('\n', 1, true)
        if not nl then
          break
        end
        local line = acc:sub(1, nl - 1)
        acc = acc:sub(nl + 1)
        if line:sub(1, 2) == 'X ' then
          -- Capability line: never reaches a response handler. An older
          -- backend has no X line, so `caps` stays empty and the preview key
          -- is a no-op instead of stalling the response FIFO.
          for cap in line:sub(3):gmatch('%S+') do
            self_ref.caps[cap] = true
          end
        elseif line == 'E' then
          -- Serve answers requests in order; each response goes to the
          -- handler that queued it, so fast key repeats never lose or
          -- misroute replies (a single pending slot used to drop the
          -- last response when the next request overtook it).
          local handler = table.remove(self_ref.handlers, 1)
          local out = self_ref.outbuf
          self_ref.outbuf = {}
          if handler then
            pf('resp')
            handler(out)
          end
        else
          self_ref.outbuf[#self_ref.outbuf + 1] = line
        end
      end
    end,
    on_stderr = function(_, data)
      if self_ref.closed then
        return
      end
      local chunk = table.concat(data, '\n'):gsub('%s+$', '')
      if chunk ~= '' then
        errbuf = (errbuf .. '\n' .. chunk):sub(-2000)
      end
    end,
    on_exit = function(_, code)
      -- A live picker whose backend died would otherwise sit on the loading
      -- placeholder forever with no explanation (bad flag, panic, killed).
      if self_ref.closed then
        return
      end
      local msg = errbuf ~= '' and errbuf or ('lusty serve exited with code ' .. code)
      vim.schedule(function()
        if not self_ref.closed then
          vim.notify('lusty: ' .. msg, vim.log.levels.ERROR)
          self_ref:close()
        end
      end)
    end,
  })
  self:send_frecency()
  self:rerank()
end

--- Public entry point; returns the picker (for tests/diagnostics).
function M.run(root)
  local p = Picker.new(root)
  p:startup()
  return p
end

--- Define the few extra highlight groups (lsc groups come from its own cache).
function M.ensure_highlights()
  -- selection styled like the neg.nvim PmenuSel bar: read the live colors
  -- (bg #005faf / fg #d1e5ff in the neg palette) so it always matches the
  -- active colorscheme, with a neg fallback
  local okp, h = pcall(api.nvim_get_hl_by_name, 'PmenuSel', true)
  local bg = 0x005faf
  local fg = 0xd1e5ff
  if okp and type(h) == 'table' then
    if h.background then
      bg = h.background
    end
    if h.foreground then
      fg = h.foreground
    end
  end
  local ok = pcall(api.nvim_set_hl, 0, 'LustyNativeSel', {
    bg = '#' .. string.format('%06x', bg),
    fg = '#' .. string.format('%06x', fg),
    bold = true,
  })
  if not ok then
    api.nvim_set_hl(0, 'LustyNativeSel', { bg = '#005faf', fg = '#d1e5ff', bold = true })
  end
  -- Selection style from the theme TOML (files/nvim/lua/lusty/theme.toml):
  -- bg/fg/bold/underline/reverse. g:LustyExplorerSelStyle (1..4) overrides
  -- with a built-in preset for quick switching.
  local sel = theme.selection()
  if sel.reverse then
    api.nvim_set_hl(0, 'LustyNativeSel', { reverse = true, bold = sel.bold ~= false })
  else
    api.nvim_set_hl(0, 'LustyNativeSel', {
      bg = sel.bg or ('#' .. string.format('%06x', bg)),
      fg = sel.fg or ('#' .. string.format('%06x', fg)),
      bold = sel.bold ~= false,
      underline = sel.underline == true,
    })
  end
  local st = tonumber(vim.g.LustyExplorerSelStyle)
  if st == 2 then
    api.nvim_set_hl(0, 'LustyNativeSel', { bg = '#006e9f', fg = '#dfffff', bold = true })
  elseif st == 3 then
    api.nvim_set_hl(0, 'LustyNativeSel', { bg = '#5e35b1', fg = '#ffffff', bold = true })
  elseif st == 4 then
    api.nvim_set_hl(0, 'LustyNativeSel', { reverse = true, bold = true })
  end
  api.nvim_set_hl(0, 'LustyPromptQuery', { fg = '#ffffff' })
  local mt = theme.match()
  api.nvim_set_hl(0, 'LustyNativeMatch', {
    fg = mt.fg or '#ffffff',
    underline = mt.underline ~= false,
  })
  api.nvim_set_hl(0, 'LustyNativeMeta', { fg = '#6c7e96' }) -- dim metadata in long view
  -- Multi-select mark (C-Space): warm tint, distinct from the match underline.
  api.nvim_set_hl(0, 'LustyNativeMark', { fg = '#ffd75f', bold = true })
  -- nearly-black but not #000000: the web/xterm layer treats exact black as
  -- the transparent default, while #0c0d14 rendered too gray on this setup
  api.nvim_set_hl(0, 'LustyNativeFloat', { bg = '#000001', fg = '#d4d4d4' })
  -- Frame one notch darker than the float body: the colorscheme's FloatBorder
  -- (VertSplit link) reads too bright against the near-black panel
  api.nvim_set_hl(0, 'LustyNativeBorder', { fg = '#3a4454', bg = '#000001' })
  -- omp.zsh path segment colors (neg.omp.json)
  api.nvim_set_hl(0, 'LustyPromptTilde', { fg = '#287373' })
  api.nvim_set_hl(0, 'LustyPromptSep', { fg = '#005faf' })
  api.nvim_set_hl(0, 'LustyPromptPath', { fg = '#95a7bc' })
end

M.ensure_highlights()

return M
