-- Generic bottom-split list picker for small item sets (native buffer
-- explorer / buffer grep). Same window geometry, colours and keys as the
-- native filesystem picker, but items come from a Lua source function
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

-- Geometry, the picker split, the keymap base, cursor/query handling and the
-- teardown are shared with the filesystem picker (`lusty.native`).
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
  -- Remember what the list was drawn for: ensure_geometry() compares against
  -- the live window size on the next key.
  self._drawn_w, self._drawn_h = self:width(), self:height()
  if self:one_line() then
    self:draw_one_line()
    return
  end
  local th = require('lusty.theme')
  local profile = th.profile()
  local w = self:width()
  local ch = self:chrome()
  local rows = self:list_rows()
  local h = self:height()
  -- fzf layout: prompt, info line, one entry per row, footer separator and
  -- the key hints (native_core.chrome drops the chrome on tiny splits).
  local top = 2 + ch.info
  local lines = {}
  for i = 1, h do
    lines[i] = string.rep(' ', w)
  end
  local cells = {}
  for r = 0, rows - 1 do
    local pos = self.offset + r
    local item = self.items[pos + 1]
    if item then
      local selected = pos == self.selected
      local marked = self.multi and self.marked[self:key_of(item)] ~= nil
      local first = selected and profile.pointer or '\u{258c}'
      local prefix = first .. (marked and profile.marker or ' ')
      local room = math.max(1, w - vim.fn.strdisplaywidth(prefix))
      local text, tw = core.fit(item.label or '', room)
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
        text_bytes = tw,
      }
    end
  end
  local prompt = core.segments_text(self:prompt_segments())
  lines[1] = prompt .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(prompt)))
  if ch.info == 1 then
    local info = core.segments_text(self:info_segments())
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
end

--- Paint the fzf chrome rows: prompt, info line, footer separator and hints.
function Pick:paint_chrome()
  local ch = self:chrome()
  local h = self:height()
  core.paint_segments(self, ns, 0, self:prompt_segments())
  if ch.info == 1 then
    core.paint_segments(self, ns, 1, self:info_segments())
  end
  if ch.footer == 2 then
    api.nvim_buf_add_highlight(self.buf, ns, 'LustySeparator', h - 2, 0, -1)
    local text = self:fitted_footer()
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyFooter', h - 1, 0, #text)
  end
end

--- Paint one list page: fzf `fg+` over the current row (no background bar),
--- `hl+` matches on it, the pointer and marker glyphs in their own colours.
function Pick:paint_cells(cells, lines)
  local profile = require('lusty.theme').profile()
  for _, cell in ipairs(cells) do
    local row = cell.line - 1
    local line = lines[cell.line] or ''
    local group = cell.item.group
    if cell.item.current and not group then
      group = 'Constant'
    end
    -- The label starts after the two prefix cells (pointer/gutter + marker).
    local start = cell.first_bytes
    if group then
      api.nvim_buf_add_highlight(
        self.buf, ns, group, row,
        start, math.min(start + cell.text_bytes, #line)
      )
    elseif cell.item.marks then
      -- Single-column grep rows: byte-accurate sub-highlights.
      for _, m in ipairs(cell.item.marks) do
        api.nvim_buf_add_highlight(
          self.buf, ns, m.group, row,
          start + m.start, math.min(start + m.finish, #line)
        )
      end
    end
    if cell.selected then
      api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', row, 0, #line)
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyPointer', row, 0, cell.first_bytes
      )
    end
    if cell.marked then
      api.nvim_buf_add_highlight(
        self.buf, ns, 'LustyNativeMark', row,
        cell.first_bytes, cell.first_bytes + #profile.marker
      )
    end
    local label = cell.item.label
    if label and self.query ~= '' and self.query:sub(1, 1) ~= '.' then
      local base = label:match('([^/]+)$') or label
      local s, e = base:lower():find(self.query:lower(), 1, true)
      if s and e then
        local origin = start + (#label - #base)
        local match_group = cell.selected and 'LustyNativeMatchSel' or 'LustyNativeMatch'
        api.nvim_buf_add_highlight(
          self.buf, ns, match_group, row, origin + s - 1, origin + e
        )
      end
    end
  end
end

--- fzf prompt row: the `❯  ` glyph and the query.
function Pick:prompt_segments()
  local add, segs = core.prompt_segments()
  add(require('lusty.theme').profile().prompt, 'LustyPrompt')
  add(self.query, 'LustyQuery')
  return segs
end

--- fzf info line: the item count, the mark count, then the `─` rule with the
--- picker title at its tail (the title used to live in the prompt).
function Pick:info_segments()
  local add, segs = core.prompt_segments()
  add('  ' .. tostring(self.total), 'LustyInfo')
  if #self.mark_order > 0 then
    add(' (' .. #self.mark_order .. ')', 'LustyInfo')
  end
  local title = self.title or ''
  local left = core.segments_text(segs)
  local fill = self:width()
    - vim.fn.strdisplaywidth(left)
    - vim.fn.strdisplaywidth(title)
    - 3
  if title ~= '' and fill > 0 then
    add(' ', 'LustyInfo')
    add(string.rep('\u{2500}', fill), 'LustySeparator')
    add(' ' .. title, 'LustyPath')
  end
  return segs
end

--- Key hints in fzf's footer shape (the two picker flavors bind different
--- sets, so the caller does not have to keep a per-instance footer).
function Pick:footer_text()
  if self.multi then
    return '[Enter] Open  [C-Space] Mark  [C-d] Delete  [C-x] One-line'
  end
  return '[Enter] Open  [C-t] Tab  [C-o] Split  [C-v] Vsplit  [C-x] One-line'
end

function Pick:fitted_footer()
  -- fzf truncates the footer instead of overflowing the window.
  return core.fit('  ' .. self:footer_text(), self:width())
end

function Pick:footer_line()
  local line = self:fitted_footer()
  return line .. string.rep(' ', math.max(0, self:width() - vim.fn.strdisplaywidth(line)))
end

--- One-line mode (g:LustyExplorerOneLine / LUSTY_ONE_LINE): a single row with
--- the prompt and the selected entry on it, no grid.
function Pick:draw_one_line()
  local item = self.items[self.selected + 1]
  core.paint_one_line(self, ns, self:prompt_segments(), item and item.label or '(no items)')
end

function Pick:column_nav(delta)
  core.column_nav(self, delta, 'refresh')
end

function Pick:handle(action)
  if self.closed then
    return
  end
  -- Cheap self-heal for a split that changed size without a display update
  -- (the resize events need one), so the grid never stays padded to the old
  -- width/height after a key.
  self:ensure_geometry()
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
  -- filesystem picker; 'refresh' is this picker's re-list entry point.
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
