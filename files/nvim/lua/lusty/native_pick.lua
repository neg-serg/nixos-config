-- Generic bottom-float list picker for small item sets (native buffer
-- explorer / buffer grep). Same window geometry, colours and keys as the
-- native filesystem float, but items come from a Lua source function
-- instead of the Rust backend, so it works for data that only nvim knows
-- (buffers, grep hits).
--
-- The source receives the current query and returns the items to show:
--   { label, name?, group?, current?, marks?, <payload> }
--   group   highlight group painted over the label text (when unselected)
--   current marks the row with the group (buffers: the current buffer)
--   marks   byte ranges for single-column rows
-- label may contain multibyte text; cells are truncated by display width.

local api = vim.api
local ns = api.nvim_create_namespace('lusty_native_pick')

local native = require('lusty.native')

local M = {}
local active = nil

-- RU (йцукен) layout to EN chars: physical keys under RU produce Cyrillic,
-- mapped the same way as in the native filesystem float.
local RU2EN = {
  ['й'] = 'q', ['ц'] = 'w', ['у'] = 'e', ['к'] = 'r', ['е'] = 't',
  ['н'] = 'y', ['г'] = 'u', ['ш'] = 'i', ['щ'] = 'o', ['з'] = 'p',
  ['х'] = '[', ['ъ'] = ']', ['ф'] = 'a', ['ы'] = 's', ['в'] = 'd',
  ['а'] = 'f', ['п'] = 'g', ['р'] = 'h', ['о'] = 'j', ['л'] = 'k',
  ['д'] = 'l', ['ж'] = ';', ['э'] = "'", ['я'] = 'z', ['ч'] = 'x',
  ['с'] = 'c', ['м'] = 'v', ['и'] = 'b', ['т'] = 'n', ['ь'] = 'm',
  ['б'] = ',', ['ю'] = '.',
}

local Pick = {}
Pick.__index = Pick

function Pick.new(opts)
  local self = setmetatable({}, Pick)
  self.title = opts.title or ''
  self.source = opts.source
  self.on_open = opts.on_open
  self.on_delete = opts.on_delete
  self.on_close = opts.on_close
  self.single = opts.single_column == true
  self.query = opts.query or ''
  self.arrow = '\u{f105}'
  self.selected = 0
  self.offset = 0
  self.items = {}
  self.total = 0
  self.maxw = 0
  self.closed = false
  self.orig_win = api.nvim_get_current_win()
  return self
end

function Pick:width()
  local ratio = tonumber(vim.g.LustyExplorerWidthRatio) or 0.8
  ratio = math.max(0.5, math.min(0.98, ratio))
  return math.max(60, math.floor(vim.o.columns * ratio))
end

function Pick:height()
  local ratio = tonumber(vim.g.LustyExplorerMaxHeightRatio) or 0.4
  ratio = math.max(0.15, math.min(0.6, ratio))
  local h = math.floor(vim.o.lines * ratio)
  return math.max(6, math.min(12, h))
end

function Pick:list_rows()
  return math.max(1, self:height() - 2)
end

function Pick:max_cols()
  if self.single then
    return 1
  end
  local w = self:width()
  local rows = self:list_rows()
  local total = math.max(self.total, 1)
  local needed = math.max(1, math.ceil(total / rows))
  local name_w = math.max(math.min(self.maxw or 12, 20), 1)
  local byw = math.max(1, math.floor((w + 2) / (name_w + 4)))
  return math.max(1, math.min(needed, byw, 8))
end

function Pick:col_width()
  local cols = self:max_cols()
  local w = self:width()
  local text_w = w - 2 * (cols - 1)
  return math.max(6, math.floor(text_w / cols))
end

function Pick:screen_count()
  return self:list_rows() * self:max_cols()
end

function Pick:open_window()
  local w, h = self:width(), self:height()
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
  api.nvim_win_set_option(win, 'winhighlight', 'Normal:LustyNativeFloat')
  api.nvim_win_set_option(win, 'winblend', 0)
  api.nvim_buf_set_lines(buf, 0, -1, false, {})
  self.buf = buf
  self.win = win
  self:setup_keymaps()
end

function Pick:setup_keymaps()
  local buf = self.buf
  local function map(lhs, action)
    api.nvim_buf_set_keymap(buf, 'n', lhs, '', {
      nowait = true,
      silent = true,
      noremap = true,
      callback = function()
        self:handle(action)
      end,
    })
  end
  for code = 32, 126 do
    local ch = string.char(code)
    local lhs = ch
    if ch == '<' then
      lhs = '<lt>'
    elseif ch == '|' then
      lhs = '<Bar>'
    elseif string.byte(ch) == 92 then -- backslash
      lhs = '<Bslash>'
    end
    map(lhs, ch)
  end
  for ru, en in pairs(RU2EN) do
    map(ru, en)
  end
  map('<Tab>', 'enter')
  map('<CR>', 'enter')
  map('<BS>', 'backspace')
  map('<C-w>', 'clear')
  map('<C-u>', 'clear')
  map('<C-n>', 'down')
  map('<Down>', 'down')
  map('<C-p>', 'up')
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
  map('<C-e>', 'last')
  map('<C-t>', 'open_tab')
  map('<C-o>', 'open_split')
  map('<C-v>', 'open_vsplit')
  map('<C-d>', 'delete')
  map('<Esc>', 'cancel')
  map('<C-c>', 'cancel')
  map('<C-g>', 'cancel')
end

function Pick:refresh()
  self.items = self.source(self.query) or {}
  self.total = #self.items
  self.maxw = 0
  for _, it in ipairs(self.items) do
    local w = vim.fn.strdisplaywidth(it.label or '')
    if w > self.maxw then
      self.maxw = w
    end
  end
  if self.selected >= self.total and self.total > 0 then
    self.selected = self.total - 1
  end
  self:ensure_visible()
  self:draw()
end

function Pick:ensure_visible()
  local screen = math.max(1, self:screen_count())
  if self.total == 0 then
    self.offset = 0
    return
  end
  if self.selected < self.offset then
    self.offset = math.max(0, math.floor(self.selected / screen) * screen)
  elseif self.selected >= self.offset + screen then
    self.offset = math.floor(self.selected / screen) * screen
  end
end

-- Truncate a label to at most w display columns (whole chars), returning
-- the text and its display width.
local function fit(text, w)
  local tw = vim.fn.strdisplaywidth(text)
  if tw <= w then
    return text, tw
  end
  local nchars = vim.fn.strchars(text)
  while tw > w and nchars > 0 do
    nchars = nchars - 1
    text = vim.fn.strcharpart(text, 0, nchars)
    tw = vim.fn.strdisplaywidth(text)
  end
  return text, tw
end

function Pick:draw()
  if self.closed or not api.nvim_buf_is_valid(self.buf) then
    return
  end
  local cols = self:max_cols()
  local col_w = self:col_width()
  local h = self:height()
  local rows = self:list_rows()
  local lines = {}
  local cells = {}
  for r = 1, rows do
    local parts = {}
    for c = 1, cols do
      local pos = self.offset + (r - 1) * cols + (c - 1)
      local item = self.items[pos - self.offset + 1]
      if item then
        local text, tw = fit(item.label or '', col_w)
        parts[c] = text .. string.rep(' ', math.max(0, col_w - tw))
        cells[#cells + 1] = {
          line = r,
          col = c,
          item = item,
          pos = pos,
          label_w = math.min(tw, col_w - 1),
          start_col = (c - 1) * (col_w + 2),
        }
      end
    end
    lines[r] = table.concat(parts, '  ')
  end
  for i = 1, h do
    if not lines[i] then
      lines[i] = ''
    end
  end
  lines[h] = self.title .. ' ' .. self.arrow .. ' ' .. self.query
    .. (self.total > 0 and (' [' .. self.total .. ']') or '')
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  local sel_col0 = 0
  for _, cell in ipairs(cells) do
    local group = cell.item.group
    if cell.item.current and not group then
      group = 'Constant'
    end
    if cell.pos == self.selected then
      sel_col0 = cell.start_col
    elseif group then
      api.nvim_buf_add_highlight(
        self.buf, ns, group, cell.line - 1, cell.start_col, cell.start_col + cell.label_w
      )
    elseif cell.item.marks and cols == 1 then
      -- single-column grep rows: byte-accurate sub-highlights
      for _, m in ipairs(cell.item.marks) do
        api.nvim_buf_add_highlight(self.buf, ns, m.group, cell.line - 1, m.start, m.finish)
      end
    end
  end
  if self.total > 0 then
    local sel_row = math.floor((self.selected - self.offset) / cols)
    api.nvim_buf_add_highlight(
      self.buf, ns, 'LustyNativeSel', sel_row, sel_col0, sel_col0 + col_w - 1
    )
  end
  self:paint_prompt(h)
end

function Pick:paint_prompt(h)
  local line = h - 1
  local segs = {}
  local col = 0
  local function add(text, group)
    if text and #text > 0 then
      segs[#segs + 1] = { col, #text, group }
      col = col + #text
    end
  end
  add(self.title, 'LustyPromptPath')
  add(' ', 'LustyPromptSep')
  add(self.arrow, 'LustyPromptSep')
  add(' ', 'LustyPromptQuery')
  add(self.query, 'LustyPromptQuery')
  if self.total > 0 then
    add(' [' .. self.total .. ']', 'LustyPromptPath')
  end
  for _, seg in ipairs(segs) do
    if seg[3] then
      api.nvim_buf_add_highlight(self.buf, ns, seg[3], line, seg[1], seg[1] + seg[2])
    end
  end
end

function Pick:column_nav(delta)
  if self.single then
    return
  end
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
  self:refresh()
end

function Pick:handle(action)
  if self.closed then
    return
  end
  if action == 'cancel' then
    self:close()
    return
  end
  if action == 'enter' or action == 'open_tab' or action == 'open_split' or action == 'open_vsplit' then
    local item = self.items[self.selected + 1]
    if item then
      local mode = action == 'enter' and 'enter' or action == 'open_tab' and 'tab' or action == 'open_split' and 'split' or 'vsplit'
      self:close()
      if self.on_open then
        pcall(self.on_open, item, mode)
      end
    end
    return
  end
  if action == 'delete' then
    local item = self.items[self.selected + 1]
    if item and self.on_delete then
      local keep = pcall(self.on_delete, item)
      if keep ~= false then
        self:refresh()
      end
    end
    return
  end
  if action == 'down' then
    if self.total > 0 then
      self.selected = (self.selected + 1) % self.total
      self:refresh()
    end
    return
  end
  if action == 'up' then
    if self.total > 0 then
      self.selected = (self.selected - 1) % self.total
      self:refresh()
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
      self:refresh()
    end
    return
  end
  if action == 'first' or action == 'last' then
    if self.total > 0 then
      self.selected = action == 'first' and 0 or (self.total - 1)
      self:refresh()
    end
    return
  end
  if action == 'clear' then
    if #self.query > 0 then
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:refresh()
    end
    return
  end
  if action == 'backspace' then
    if #self.query > 0 then
      self.query = self.query:sub(1, -2)
      self.selected = 0
      self.offset = 0
      self:refresh()
    end
    return
  end
  -- typing
  if #action == 1 then
    self.query = self.query .. action
    self.selected = 0
    self.offset = 0
    self:refresh()
  end
end

function Pick:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.win and api.nvim_win_is_valid(self.win) then
    pcall(api.nvim_win_close, self.win, true)
  end
  if self.buf and api.nvim_buf_is_valid(self.buf) then
    pcall(api.nvim_buf_delete, self.buf, { force = true })
  end
  if api.nvim_win_is_valid(self.orig_win) then
    pcall(api.nvim_set_current_win, self.orig_win)
  end
  active = nil
  if self.on_close then
    pcall(self.on_close, self)
  end
end

-- Open one list picker (no-op when another is already active).
function M.pick(opts)
  if active then
    return nil
  end
  native.ensure_highlights()
  local p = Pick.new(opts)
  active = p
  p:open_window()
  p:refresh()
  return p
end

function M.active_pick()
  return active
end

return M
