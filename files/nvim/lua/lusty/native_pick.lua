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
--
-- With opts.multi = true the picker binds C-Space: it marks the item under the
-- cursor (keyed stably via opts.key, default item.path/bufnr/label, so marks
-- survive refresh) and highlights it with LustyNativeMark. Enter then calls
-- opts.on_open_many(items, mode) when provided, and C-d calls opts.on_delete
-- for every marked item. opts.markable(item) can veto marking (e.g. dirs).

local api = vim.api
local ns = api.nvim_create_namespace('lusty_native_pick')

local native = require('lusty.native')
local core = require('lusty.native_core')

local M = {}
local active = nil

local Pick = {}
Pick.__index = Pick

-- Geometry, the float window, the keymap base, cursor/query handling and the
-- teardown are shared with the filesystem float (`lusty.native`).
core.bind(Pick)

function Pick.new(opts)
  local self = setmetatable({}, Pick)
  self.title = opts.title or ''
  self.source = opts.source
  self.on_open = opts.on_open
  self.on_delete = opts.on_delete
  self.on_close = opts.on_close
  self.keys = opts.keys or {}
  self.single = opts.single_column == true
  self.multi = opts.multi == true
  self.on_open_many = opts.on_open_many
  self.key_fn = opts.key
  self.markable = opts.markable
  self.marked = {} -- stable key -> item
  self.mark_order = {} -- { { key = ..., item = ... }, ... } in mark order
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

function Pick:key_of(item)
  if self.key_fn then
    return self.key_fn(item)
  end
  return item.path or item.bufnr or item.label
end

function Pick:setup_keymaps()
  local actions = {
    ['<C-w>'] = 'clear',
    ['<C-e>'] = 'last',
    ['<C-d>'] = 'delete',
  }
  if self.multi then
    -- Multi-select (C-Space) is only bound when the caller asks for it.
    actions['<C-Space>'] = 'mark'
  end
  -- Caller-supplied keys are raw callbacks (e.g. the MRU files/dirs toggle).
  core.setup_keymaps(self, { actions = actions, raw = self.keys })
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
        local text, tw = core.fit(item.label or '', col_w)
        parts[c] = text .. string.rep(' ', math.max(0, col_w - tw))
        cells[#cells + 1] = {
          line = r,
          col = c,
          item = item,
          pos = pos,
          label_w = tw, -- colour the full visible label, incl. the last char
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
    .. (#self.mark_order > 0 and (' (' .. #self.mark_order .. ' marked)') or '')
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
    -- Underline matched query letters in the label (incl. the selected row,
    -- so the match survives the selection bar).
    local label = cell.item.label
    if label and self.query ~= '' and self.query:sub(1, 1) ~= '.' then
      local base = label:match('([^/]+)$') or label
      local s, e = base:lower():find(self.query:lower(), 1, true)
      if s and e then
        local origin = cell.start_col + (#label - #base)
        api.nvim_buf_add_highlight(
          self.buf, ns, 'LustyNativeMatch', cell.line - 1, origin + s - 1, origin + e
        )
      end
    end
    if self.multi and self.marked[self:key_of(cell.item)] then
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyNativeMark', cell.line - 1, cell.start_col, cell.start_col + cell.label_w
      )
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
  local add, segs = core.prompt_segments()
  add(self.title, 'LustyPromptPath')
  add(' ', 'LustyPromptSep')
  add(self.arrow, 'LustyPromptSep')
  add(' ', 'LustyPromptQuery')
  add(self.query, 'LustyPromptQuery')
  if self.total > 0 then
    add(' [' .. self.total .. ']', 'LustyPromptPath')
  end
  if #self.mark_order > 0 then
    add(' (' .. #self.mark_order .. ' marked)', 'LustyPromptPath')
  end
  core.paint_segments(self, ns, line, segs)
end

function Pick:column_nav(delta)
  core.column_nav(self, delta, 'refresh')
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
      if self.multi and #self.mark_order > 0 and self.on_open_many then
        local items = {}
        for _, m in ipairs(self.mark_order) do
          items[#items + 1] = m.item
        end
        self:close()
        pcall(self.on_open_many, items, mode)
        return
      end
      self:close()
      if self.on_open then
        pcall(self.on_open, item, mode)
      end
    end
    return
  end
  if action == 'mark' then
    local item = self.items[self.selected + 1]
    if item and (not self.markable or self.markable(item)) then
      local key = self:key_of(item)
      if self.marked[key] then
        self.marked[key] = nil
        for i, m in ipairs(self.mark_order) do
          if m.key == key then
            table.remove(self.mark_order, i)
            break
          end
        end
      else
        self.marked[key] = item
        self.mark_order[#self.mark_order + 1] = { key = key, item = item }
      end
      self:draw()
    end
    return
  end
  if action == 'delete' then
    if self.multi and #self.mark_order > 0 and self.on_delete then
      -- Delete the whole marked set in one go, then drop the stale marks.
      for _, m in ipairs(self.mark_order) do
        pcall(self.on_delete, m.item)
      end
      self.marked = {}
      self.mark_order = {}
      self:refresh()
      return
    end
    local item = self.items[self.selected + 1]
    if item and self.on_delete then
      local keep = pcall(self.on_delete, item)
      if keep ~= false then
        self:refresh()
      end
    end
    return
  end
  -- Cursor movement, column/page jumps and query editing are shared with the
  -- filesystem float; 'refresh' is this picker's re-list entry point.
  core.handle_common(self, action, 'refresh')
end

function Pick:close()
  if self.closed then
    return
  end
  core.close(self)
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
