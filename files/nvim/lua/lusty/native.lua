-- Lusty picker: Rust backend (lusty serve) rendered as a regular bottom split
-- with real highlights — no floating window and no frame. No terminal buffer
-- involved, so it renders reliably even when nvim itself runs inside a web
-- xterm. This is the only picker implementation (the historical Lua port was
-- removed). The layout follows the fzf profile in theme.toml: prompt on top,
-- info line under it, one entry per row, footer hints.
--
-- Backend protocol (plain lines, tab separated):
--   Q <from> <to> <query> [sort] -> "N <matched> <total>" + "W <maxw>" + "R <i> <kind> <label>\t<path>" rows + "E"
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
local core = require('lusty.native_core')

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
    prof_t0 = vim.uv.hrtime()
  end
  local f = io.open(prof_path, 'a')
  if f then
    f:write(string.format('%.2f %s\n', (vim.uv.hrtime() - prof_t0) / 1e6, tag))
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

-- Geometry, the picker split, the keymap base, cursor/query handling and the
-- teardown are shared with the generic list picker (`lusty.native_pick`).
core.bind(Picker)

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

--- Long-view column mask: LUSTY_COLUMNS wins over g:LustyExplorerColumns;
--- unknown tokens are ignored, an empty result means all fields
--- (perm,user,size,time). CLI flags do not apply to the nvim picker.
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
--- picker is redrawn. Skipped while another request is in flight; the draw
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

--- Preview pane width: LUSTY_PREVIEW_WIDTH / g:LustyExplorerPreviewWidth,
--- else ~35% of the editor, clamped so the picker still fits beside it.
function Picker:preview_width()
  local w = tonumber(os.getenv('LUSTY_PREVIEW_WIDTH')) or tonumber(vim.g.LustyExplorerPreviewWidth)
  if not w or w < 8 then
    w = math.max(24, math.floor(vim.o.columns * 0.35))
  end
  return math.max(8, math.min(w, vim.o.columns - 20))
end

--- Open the preview pane as a vertical split to the right of the picker split
--- (same height, no frame; focus stays on the picker). The picker narrows to
--- the remaining columns and is redrawn, so the grid re-flows instead of
--- overflowing. Reopen on C-r to re-request the content at the new size.
function Picker:open_preview()
  if not self.win or not api.nvim_win_is_valid(self.win) then
    return
  end
  local w = self:preview_width()
  local picker_win = self.win
  api.nvim_set_current_win(picker_win)
  -- `rightbelow vsplit` splits the picker window itself, so the pane inherits
  -- its height and lands directly beside it; the width is set explicitly.
  vim.cmd('noautocmd rightbelow vsplit')
  local win = api.nvim_get_current_win()
  local buf = api.nvim_create_buf(false, true)
  api.nvim_win_set_buf(win, buf)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].bufhidden = 'wipe'
  core.apply_window_opts(win)
  pcall(api.nvim_win_set_width, win, w)
  api.nvim_set_current_win(picker_win)
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
  -- The picker got its columns back: re-flow the grid (draw is a no-op while
  -- the whole picker is closing).
  if self.win and api.nvim_win_is_valid(self.win) then
    self:draw()
  end
end

function Picker:toggle_preview()
  if self:one_line() then
    vim.notify('lusty: the preview pane needs the grid (one-line mode)', vim.log.levels.WARN)
    return
  end
  if not self.caps.preview then
    vim.notify('lusty: this backend has no preview (no X preview)', vim.log.levels.WARN)
    return
  end
  self.preview_on = not self.preview_on
  if self.preview_on then
    self:open_preview()
    -- The pane took its columns from the picker: re-flow the grid first, then
    -- request the content for the now smaller pane.
    self:draw()
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

function Picker:setup_keymaps()
  core.setup_keymaps(self, {
    actions = {
      ['<S-CR>'] = 'enter',
      -- C-w: parent directory (after the typed text is cleared).
      ['<C-w>'] = 'updir',
      -- C-e: open the typed text as a new buffer (Lua-port parity; parent
      -- dirs are created). C-d: cycle the search depth 1..6 at runtime
      -- (buffers/grep use C-d for delete instead; this is the filesystem picker).
      ['<C-e>'] = 'create',
      ['<C-d>'] = 'cycle_depth',
      ['<C-Space>'] = 'mark',
      -- C-y: sort cycle (C-s collides with terminal/kitty flow control)
      ['<C-y>'] = 'cycle_sort',
      ['<C-l>'] = 'toggle_long',
      -- C-r: preview pane (only when the backend advertises `X preview`).
      ['<C-r>'] = 'toggle_preview',
    },
  })
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
      -- "N <matched> <total>": the backend reports the listing size as a
      -- second token, so the info line can show fzf's `matched/total`
      -- counter. An older backend sends only the matched count.
      local n, all = ln:match('^N (%d+)%s*(%d*)$')
      if n then
        total = tonumber(n)
        if all ~= '' then
          self.listing_total = tonumber(all)
        end
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
  -- Remember what the grid was drawn for: ensure_geometry() compares against
  -- the live window size on the next key.
  self._drawn_w, self._drawn_h = self:width(), self:height()
  if self:one_line() then
    self:draw_one_line()
    return
  end
  local w = self:width()
  local ch = self:chrome()
  local rows = self:list_rows()
  local h = self:height()
  -- fzf layout: the prompt is the first row, the info line sits right under
  -- it, the entries follow and the footer (separator + key hints) closes the
  -- split. A short split drops the footer first, then the info line
  -- (native_core.chrome).
  local top = 2 + ch.info
  local profile = theme.profile()
  local lines = {}
  for i = 1, h do
    lines[i] = string.rep(' ', w)
  end
  local cells = {}
  if self.loading then
    -- First listing still in flight: the fzf chrome with a dim ellipsis
    -- instead of a stale list.
    if ch.info == 1 then
      lines[2] = '  …' .. string.rep(' ', math.max(0, w - 3))
    end
  else
    for r = 0, rows - 1 do
      local pos = self.offset + r
      local item = self.window[r + 1]
      if item then
        local selected = pos == self.selected
        local marked = self.marked[item.path] ~= nil
        local name = item.label
        local icon_pre = ''
        if self.icons then
          icon_pre = icon_for(item) .. ' '
          name = icon_pre .. name
        elseif item.kind == 'd' then
          name = name .. '/'
        end
        local meta = ''
        if self.long and item.meta and item.meta ~= '' then
          meta = item.meta .. ' '
        end
        -- fzf line prefix: the pointer on the current row, the gutter bar
        -- elsewhere, then the marker column (the ✓ glyph on marked rows).
        local first = selected and profile.pointer or '\u{258c}'
        local prefix = first .. (marked and profile.marker or ' ')
        local body = meta .. name
        local room = math.max(1, w - vim.fn.strdisplaywidth(prefix))
        local text = core.fit(body, room)
        local line = prefix .. text
        line = line .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(line)))
        lines[top + r] = line
        cells[#cells + 1] = {
          line = top + r,
          item = item,
          pos = pos,
          selected = selected,
          marked = marked,
          first_bytes = #first,
          prefix_bytes = #prefix,
          meta = meta,
          icon_bytes = #icon_pre,
          name_start = #prefix + #meta,
          text_bytes = math.max(0, #text - #meta),
        }
      end
    end
  end
  local prompt = self:prompt_text()
  lines[1] = prompt .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(prompt)))
  if ch.info == 1 then
    local info = self:info_text()
    lines[2] = info .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(info)))
  end
  if ch.footer == 2 then
    lines[h - 1] = string.rep('\u{2500}', w)
    lines[h] = self:footer_line()
  end
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)
  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  self:paint_chrome()
  self:paint_cells(cells, lines)
  pf('drawn')
  self:ensure_meta()
end

--- Paint the fzf chrome rows: prompt, info line, footer separator and hints.
function Picker:paint_chrome()
  local ch = self:chrome()
  local h = self:height()
  self:paint_prompt(0)
  if ch.info == 1 then
    core.paint_segments(self, ns, 1, self:info_segments())
  end
  if ch.footer == 2 then
    api.nvim_buf_add_highlight(self.buf, ns, 'LustySeparator', h - 2, 0, -1)
    local text = self:fitted_footer()
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyFooter', h - 1, 0, #text)
  end
end

--- Paint one list page. The current row takes fzf's `fg+` over the whole line
--- (no background bar), its matches take `hl+`, the pointer keeps the pointer
--- colour and the marker glyph its own; every other row keeps LS_COLORS and
--- the `hl` match tone.
function Picker:paint_cells(cells, lines)
  local profile = theme.profile()
  for _, cell in ipairs(cells) do
    local row = cell.line - 1
    local line = lines[cell.line] or ''
    local entry = {
      name = basename(cell.item.label),
      is_dir = cell.item.kind == 'd',
      is_link = cell.item.kind == 'l',
      path = cell.item.path,
    }
    local group = lsc.group_for(entry)
    if group then
      api.nvim_buf_add_highlight(
        self.buf, ns, group, row,
        cell.name_start, math.min(cell.name_start + cell.text_bytes, #line)
      )
    end
    if cell.meta ~= '' and not cell.selected then
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyNativeMeta', row,
        cell.prefix_bytes, cell.prefix_bytes + #cell.meta
      )
    end
    if cell.selected then
      -- fzf's current line: no background, just fg+ over the whole row.
      api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', row, 0, #line)
      -- The pointer keeps its own colour on top of fg+ (pointer == hl+ in
      -- this profile, but the roles stay separate).
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyPointer', row, 0, cell.first_bytes
      )
    end
    if cell.marked then
      local from = cell.first_bytes
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyNativeMark', row, from,
        from + #profile.marker
      )
    end
    -- Approximate fuzzy-match highlight: the first plain case-insensitive
    -- occurrence of the query in the entry basename. Painted last, after the
    -- current line, so hl+ wins over fg+.
    local q = self.query
    if q ~= '' and q:sub(1, 1) ~= '.' then
      local base = basename(cell.item.label)
      local s, e = base:lower():find(q:lower(), 1, true)
      if s and e then
        local name_start = cell.name_start + (cell.icon_bytes or 0)
        local lstart = #cell.item.label - #base
        local match_group = cell.selected and 'LustyNativeMatchSel' or 'LustyNativeMatch'
        api.nvim_buf_add_highlight(
          self.buf, ns, match_group, row,
          name_start + lstart + s - 1, name_start + lstart + e
        )
      end
    end
  end
end

--- fzf prompt row: the `❯  ` glyph and the query. The counters moved to the
--- info line; the browsed directory rides at the right-hand tail of that line
--- (the standalone TUI puts it in the border label, a split has no border).
function Picker:prompt_segments()
  local add, segs = core.prompt_segments()
  add(theme.profile().prompt, 'LustyPrompt')
  add(self.query, 'LustyQuery')
  return segs
end

--- Plain text of the prompt line (the same bytes the segments paint).
function Picker:prompt_text()
  return core.segments_text(self:prompt_segments())
end

--- Paint the prompt row; `line` is 0-based for core.paint_segments.
function Picker:paint_prompt(line)
  core.paint_segments(self, ns, line, self:prompt_segments())
end

--- Tildified browsed directory, as shown at the tail of the info line.
function Picker:path_text()
  local home = os.getenv('HOME') or ''
  local path = self.root or ''
  if
    home ~= ''
    and path:sub(1, #home) == home
    and (#path == #home or path:sub(#home + 1, #home + 1) == '/')
  then
    return '~' .. path:sub(#home + 1)
  end
  return path
end

--- fzf info line: `matched/total` (serve reports both numbers), the mark
--- count as fzf's `--multi` appends, the depth and the sort order, then the
--- `─` rule that fills the row and the browsed directory at its tail.
function Picker:info_segments()
  local add, segs = core.prompt_segments()
  local total = self.listing_total or self.total
  add('  ' .. tostring(self.total) .. '/' .. tostring(total), 'LustyInfo')
  if #self.mark_order > 0 then
    add(' (' .. #self.mark_order .. ')', 'LustyInfo')
  end
  add('  d' .. tostring(self.depth), 'LustyInfo')
  if self.sort > 0 then
    add('  ' .. SORT_LABELS[self.sort + 1], 'LustyInfo')
  end
  local path = self:path_text()
  local left = core.segments_text(segs)
  local fill = self:width()
    - vim.fn.strdisplaywidth(left)
    - vim.fn.strdisplaywidth(path)
    - 3
  if fill > 0 then
    add(' ', 'LustyInfo')
    add(string.rep('\u{2500}', fill), 'LustySeparator')
    add(' ' .. path, 'LustyPath')
  end
  return segs
end

function Picker:info_text()
  return core.segments_text(self:info_segments())
end

--- Key hints in fzf's footer shape; the filesystem picker overrides this in
--- the list pickers where the key set differs.
function Picker:footer_text()
  return '[C-l] Long  [C-y] Sort  [C-r] Preview  [C-d] Depth  [C-Space] Mark  [C-x] One-line'
end

function Picker:fitted_footer()
  -- fzf truncates the footer instead of overflowing the window.
  return core.fit('  ' .. self:footer_text(), self:width())
end

function Picker:footer_line()
  local line = self:fitted_footer()
  return line .. string.rep(' ', math.max(0, self:width() - vim.fn.strdisplaywidth(line)))
end

--- One-line mode (g:LustyExplorerOneLine / LUSTY_ONE_LINE): a single row with
--- the prompt and the entries on it, no grid. The selected entry comes first
--- (it carries the bar), followed by the entries after it that still fit: one
--- row must show the variants on offer, not just the cursor.
function Picker:draw_one_line()
  if self.loading then
    core.paint_one_line(self, ns, self:prompt_segments(), '…')
    self:ensure_meta()
    return
  end
  local cells = {}
  local start = self.selected - self.offset + 1
  for i = start, #self.window do
    local item = self.window[i]
    if not item then
      break
    end
    local text = (self.icons and (icon_for(item) .. ' ') or '') .. item.label
    if item.kind == 'd' and not self.icons then
      text = text .. '/'
    end
    if self.long and item.meta and item.meta ~= '' then
      text = item.meta .. ' ' .. text
    end
    cells[#cells + 1] = { text = text, selected = (i == start) }
    -- The painter stops at the row width; this only bounds the work.
    if #cells >= 24 then
      break
    end
  end
  if #cells == 0 then
    cells[1] = { text = '(no matches)', selected = true }
  end
  core.paint_one_line(self, ns, self:prompt_segments(), cells)
  self:ensure_meta()
end

--- Move one grid column left/right (wrap), mirroring the Lua port.
function Picker:column_nav(delta)
  core.column_nav(self, delta, 'rerank')
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
  core.close(self)
end

function Picker:handle(action)
  if self.closed then
    return
  end
  -- Cheap self-heal for a split that changed size without a display update
  -- (the resize events need one), so the grid never stays padded to the old
  -- width/height after a key.
  self:ensure_geometry()
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
  -- Cursor movement, column/page jumps, query editing and plain typing are
  -- shared with the generic list picker; '/' is intercepted before the typed
  -- character is appended, and a dotfile-mode flip restarts the backend
  -- instead of scheduling a rerank.
  core.handle_common(self, action, 'rerank', {
    query_refresh = 'schedule_rerank',
    on_char = function(picker, ch)
      if ch == '/' then
        picker:slash_enter()
        return true
      end
      return false
    end,
    on_query = function(picker)
      return picker:maybe_toggle_dots()
    end,
  })
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

--- Re-open the picker on another root (or depth): close + a fresh picker over
--- the restored layout. The split height is carried over — a split is
--- user-resizable, and navigating (Enter on a dir, C-w, C-d) must not snap it
--- back to the default.
function Picker:restart(root, depth)
  local win_h = self.grid_h or self:height()
  local override = self.one_line_override
  local grid_h = self.grid_h
  self:close() -- restores the caller window
  local np = Picker.new(root, depth or self.depth)
  np.win_h = win_h
  np.one_line_override = override
  np.grid_h = grid_h
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
    -- (,. then C-r) reflects where the filesystem picker was used.
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
  local c = theme.colors()
  local p = theme.profile()
  local function hl(group, spec)
    local ok = pcall(api.nvim_set_hl, 0, group, spec)
    if not ok then
      api.nvim_set_hl(0, group, { link = 'Normal' })
    end
  end
  -- The picker body: fzf's list background/foreground.
  hl('LustyNativeFloat', { bg = c.bg, fg = c.fg })
  hl('LustyNativeBorder', { fg = c.border, bg = c.bg })
  -- Chrome roles: prompt, query, info line, separator and footer.
  hl('LustyPrompt', { fg = c.prompt })
  hl('LustyQuery', { fg = c.input })
  hl('LustyInfo', { fg = c.info })
  hl('LustyPath', { fg = c.info })
  hl('LustySeparator', { fg = c.separator, bg = c.bg })
  hl('LustyFooter', { fg = c.footer, underline = p.footer_underline ~= false })
  -- List roles: fzf fg+, pointer, marker, hl and hl+.
  hl('LustyPointer', { fg = c.pointer })
  hl('LustyNativeMark', { fg = c.marker })
  hl('LustyNativeSel', { fg = c.fg_current })
  hl('LustyNativeMatch', { fg = c.hl })
  hl('LustyNativeMatchSel', { fg = c.hl_current })
  hl('LustyNativeMeta', { fg = c.info })
  -- Legacy names still referenced by the prompt/one-line helpers.
  hl('LustyPromptSep', { fg = c.prompt })
  hl('LustyPromptQuery', { fg = c.input })
  hl('LustyPromptPath', { fg = c.info })
  hl('LustyPromptTilde', { fg = c.info })
end

M.ensure_highlights()

return M
