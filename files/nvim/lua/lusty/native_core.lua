-- Shared core of the native Lusty pickers: the filesystem picker
-- (`lusty.native`, Rust backend) and the generic list picker
-- (`lusty.native_pick`, Lua source). Both render the same frameless
-- full-width bottom split with the same geometry, colours and key handling,
-- so the common half lives here; each picker only supplies the parts that
-- differ (long view vs item groups, backend job vs Lua source).
--
-- The module is a stateless method bag: functions take the picker as their
-- first argument, so a picker class either binds the shared methods with
-- `core.bind(cls)` or wraps them with its own re-list method.

local api = vim.api

-- RU (ЙЦУКЕН) layout to EN chars, shared with the other pickers.
local RU2EN = require('lusty.ru2en')

local M = {}

-- ---------------------------------------------------------------------------
-- Geometry

--- Picker width in display cells. Once the split exists its real width is
--- authoritative: the split spans the tabpage and only narrows while the
--- preview pane holds the right side. Before that the editor width is the best
--- available guess (used by the pre-open geometry queries).
function M.width(self)
  if self.win and api.nvim_win_is_valid(self.win) then
    return math.max(1, api.nvim_win_get_width(self.win))
  end
  return math.max(1, vim.o.columns)
end

--- One-line mode: the picker is a single row and the prompt and the selected
--- entry share it (no grid). The per-picker `one_line_override` (set by the
--- C-x toggle) wins over `LUSTY_ONE_LINE`, which wins over
--- `g:LustyExplorerOneLine`; the option is read live so it can be flipped
--- between runs.
function M.one_line(self)
  if self.one_line_override ~= nil then
    return self.one_line_override
  end
  local e = os.getenv('LUSTY_ONE_LINE')
  if e ~= nil and e ~= '' then
    return e == '1' or e == 'true'
  end
  local gv = vim.g.LustyExplorerOneLine
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

--- Picker height in rows. Once open it is the window height, so an interactive
--- resize (or the preview open/close) is picked up by the next draw; before
--- that it is the requested height: the height the split had before a
--- re-open (`win_h`, see Picker:restart — a split is user-resizable, so
--- navigating must not snap it back), else LUSTY_ROWS as in the standalone
--- `--rows`, else fzf's `--height=16`. A split has no border rows, so the env
--- value is the window height as is. The one-line mode always asks for a
--- single row and ensure_geometry() keeps the window there.
function M.height(self)
  if self:one_line() then
    return 1
  end
  if self.win and api.nvim_win_is_valid(self.win) then
    return math.max(1, api.nvim_win_get_height(self.win))
  end
  if self.win_h then
    return math.max(2, math.min(self.win_h, vim.o.lines - 3))
  end
  local envr = tonumber(os.getenv('LUSTY_ROWS'))
  if envr and envr >= 3 then
    return math.max(2, math.min(envr, vim.o.lines - 3))
  end
  return math.min(16, math.max(1, vim.o.lines - 3))
end

--- fzf chrome rows: the prompt (always), the info line right under it and the
--- two-row footer (separator + key hints). A short split drops the footer
--- first and then the info line, so a tiny window still shows an entry.
function M.chrome(self)
  local h = self:height()
  local info = h >= 4 and 1 or 0
  local footer = h >= 6 and 2 or 0
  return { info = info, footer = footer }
end

function M.list_rows(self)
  -- Entry rows inside the window: everything but the fzf chrome, so the list
  -- fills the split instead of leaving its last rows empty.
  local c = M.chrome(self)
  return math.max(1, self:height() - 1 - c.info - c.footer)
end

--- Entry columns. fzf is a one-entry-per-line picker, so the pickers render a
--- single column; the function stays as the seam the layout code (and the
--- standalone grid view) already call.
function M.max_cols(self)
  return 1
end

function M.col_width(self)
  local cols = self:max_cols()
  local w = self:width()
  -- remaining width for the text columns after the separators
  local text_w = w - 2 * (cols - 1)
  return math.max(6, math.floor(text_w / cols))
end

--- Number of positions covered by one screenful of the grid. The one-line mode
--- keeps a normal page behind the single visible row: C-n/C-p then walk the
--- already fetched list instead of asking the backend once per keystroke.
function M.screen_count(self)
  if self:one_line() then
    return 50
  end
  return self:list_rows() * self:max_cols()
end

-- ---------------------------------------------------------------------------
-- Window

--- Window options shared by the picker split and its preview pane: the panel
--- look without any frame. A regular window has no border; the window's own
--- statusline is blanked and painted in the body colour, so the split reads as
--- one flat panel instead of a boxed float, and the gutter options are off so
--- the grid starts at column 1. `statuscolumn` must go too: `:split` copies
--- the window-local options of the source window, and a rendered status column
--- would push the grid right while the rows are padded to the full width.
function M.apply_window_opts(win)
  local o = vim.wo[win]
  o.wrap = false
  o.number = false
  o.relativenumber = false
  o.signcolumn = 'no'
  o.statuscolumn = ''
  o.foldcolumn = '0'
  o.cursorline = false
  o.cursorcolumn = false
  o.colorcolumn = ''
  o.list = false
  o.spell = false
  o.scrolloff = 0
  o.sidescrolloff = 0
  -- Normal is the panel body, WinSeparator the single line against the window
  -- above / the preview, and the statusline groups blend the picker's own
  -- statusline row into it. A literal space hides the buffer name: an empty
  -- 'statusline' would fall back to the global value.
  o.winhighlight = 'Normal:LustyNativeFloat,WinSeparator:LustyNativeBorder,'
    .. 'StatusLine:LustyNativeFloat,StatusLineNC:LustyNativeFloat,EndOfBuffer:LustyNativeFloat'
  o.statusline = ' '
  o.winbar = ''
  o.fillchars = 'eob: '
end

function M.open_window(self)
  local h = self:height()
  local buf = api.nvim_create_buf(false, true)
  -- Snapshot the window sizes of the tab before splitting: nvim re-equalizes
  -- the layout when a split is opened and closed ('equalalways', default on),
  -- so a plain cancel would hand back the user's layout with different window
  -- heights. The snapshot is replayed in close(), after the split is gone.
  self.restore_cmd = vim.fn.winrestcmd()
  self.restore_tab = api.nvim_get_current_tabpage()
  -- A regular bottom split instead of a floating window: `botright` pins the
  -- picker to the full-width bottom row of the tabpage (a vertical layout above
  -- stays intact) and closing the window restores that layout. `noautocmd`
  -- keeps the temporary window — it still shows the current buffer — from
  -- firing the user's WinNew/BufEnter hooks.
  vim.cmd('noautocmd botright split')
  local win = api.nvim_get_current_win()
  api.nvim_win_set_buf(win, buf)
  api.nvim_win_set_height(win, h)
  vim.bo[buf].buftype = 'nofile'
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = true
  vim.bo[buf].bufhidden = 'wipe'
  M.apply_window_opts(win)
  api.nvim_buf_set_lines(buf, 0, -1, false, {})
  self.buf = buf
  self.win = win
  self:setup_keymaps()
  -- Modal picker: if focus ever leaves the picker (e.g. a click on the buffer
  -- above), pull it straight back. Otherwise letters typed outside land in the
  -- original buffer, where 'c' starts the change operator and nvim waits a
  -- timeoutlen for a motion.
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
  -- A split follows the editor/layout, unlike a fixed-size float: redraw when
  -- the geometry changes (terminal resize, the preview pane opening or
  -- closing, `:only`), otherwise the grid stays padded to the old width.
  self.resize_grp = api.nvim_create_augroup('LustyPickResize' .. buf, { clear = true })
  api.nvim_create_autocmd({ 'VimResized', 'WinResized' }, {
    group = self.resize_grp,
    callback = function()
      self_ref:on_win_resized()
    end,
  })
  -- The window or the buffer can disappear outside the key handlers (`:q`,
  -- `:close`, `:only`, a plugin, a session restore). Tie the teardown to that
  -- death, otherwise `lusty serve` keeps running with no UI to feed.
  self.dead_grp = api.nvim_create_augroup('LustyPickDead' .. buf, { clear = true })
  api.nvim_create_autocmd('WinClosed', {
    group = self.dead_grp,
    pattern = tostring(win),
    callback = function()
      self_ref:close()
    end,
  })
  api.nvim_create_autocmd('BufWipeout', {
    group = self.dead_grp,
    buffer = buf,
    callback = function()
      self_ref:close()
    end,
  })
end

--- Redraw once when the drawn grid no longer matches the window. The resize
--- events are delivered after a display update, so a size change made through
--- the API (or in a headless run, where nothing is ever displayed) would leave
--- a stale grid until the next listing; every key checks this first.
function M.ensure_geometry(self)
  if self.closed or not self.win or not api.nvim_win_is_valid(self.win) then
    return
  end
  -- The one-line mode owns exactly one row: any other height (a resize, a
  -- leftover layout) is snapped back instead of leaving a half-empty window.
  if self:one_line() and api.nvim_win_get_height(self.win) ~= 1 then
    pcall(api.nvim_win_set_height, self.win, 1)
  end
  if self._drawn_w ~= api.nvim_win_get_width(self.win)
    or self._drawn_h ~= api.nvim_win_get_height(self.win)
  then
    self:draw()
  end
end

--- Redraw after the split geometry changed. Pickers with side panes also
--- re-request their content, but only when the pane really changed size: the
--- preview response is keyed by width/height, so clearing the key here would
--- turn every unrelated resize into a full backend render (chafa/git/man) for
--- each display frame of an interactive drag.
function M.on_win_resized(self)
  if self.closed then
    return
  end
  vim.schedule(function()
    if self.closed or not self.buf or not api.nvim_buf_is_valid(self.buf) then
      return
    end
    self:draw()
    if self.preview_on and self.refresh_preview then
      self:refresh_preview()
    end
  end)
end

--- Switch between the one-line row and the grid (C-x) without losing the query
--- or the selection: the split stays where it is, only its height changes. The
--- collapsed grid height is remembered per picker, so two toggles land back on
--- the height the user had. `refresh` re-lists for the new geometry (the
--- one-line row keeps a wider page behind it than the grid does).
function M.toggle_one_line(self, refresh)
  if not self.win or not api.nvim_win_is_valid(self.win) then
    return
  end
  if self:one_line() then
    self.one_line_override = false
    local h = self.grid_h or tonumber(os.getenv('LUSTY_ROWS')) or 6
    self.grid_h = nil
    pcall(api.nvim_win_set_height, self.win, math.max(2, math.min(h, vim.o.lines - 3)))
  else
    self.grid_h = api.nvim_win_get_height(self.win)
    self.one_line_override = true
    pcall(api.nvim_win_set_height, self.win, 1)
    -- A pane needs the grid: close the preview instead of leaving it next to a
    -- one-row split.
    if self.preview_on then
      self.preview_on = false
      if self.close_preview then
        self:close_preview()
      end
    end
  end
  self:ensure_visible()
  if refresh then
    self[refresh](self)
  else
    self:draw()
  end
end

-- ---------------------------------------------------------------------------
-- Keymaps

--- Special keys every picker binds to the same action. Printable ASCII and the
--- RU layout aliases are added separately; per-picker keys go through
--- `opts.actions` (lhs -> action, overrides the base) and `opts.raw`
--- (lhs -> function(self), caller-supplied raw callbacks).
local BASE_KEYS = {
  { '<Tab>', 'enter' },
  { '<CR>', 'enter' },
  -- C-x: switch between the one-line row and the grid (keeps query/selection).
  { '<C-x>', 'toggle_one_line' },
  { '<BS>', 'backspace' },
  { '<C-h>', 'backspace' },
  { '<C-n>', 'down' },
  { '<C-j>', 'down' },
  { '<Down>', 'down' },
  { '<C-p>', 'up' },
  { '<C-k>', 'up' },
  { '<Up>', 'up' },
  { '<C-f>', 'colnext' },
  { '<Right>', 'colnext' },
  { '<C-b>', 'colprev' },
  { '<Left>', 'colprev' },
  { '<PageDown>', 'pagedown' },
  { '<PageUp>', 'pageup' },
  { '<Home>', 'first' },
  { '<C-a>', 'first' },
  { '<End>', 'last' },
  { '<C-u>', 'clear' },
  { '<C-t>', 'open_tab' },
  { '<C-o>', 'open_split' },
  { '<C-v>', 'open_vsplit' },
  { '<Esc>', 'cancel' },
  { '<C-c>', 'cancel' },
  { '<C-g>', 'cancel' },
}

function M.setup_keymaps(self, opts)
  opts = opts or {}
  local buf = self.buf
  local self_ref = self
  local function map(lhs, action)
    api.nvim_buf_set_keymap(buf, 'n', lhs, '', {
      nowait = true,
      silent = true,
      noremap = true,
      callback = function()
        self_ref:handle(action)
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
    elseif ch == '\\' then
      lhs = '<Bslash>'
    end
    map(lhs, ch)
  end
  for ru, en in pairs(RU2EN) do
    map(ru, en)
  end
  for _, kv in ipairs(BASE_KEYS) do
    map(kv[1], kv[2])
  end
  for lhs, action in pairs(opts.actions or {}) do
    map(lhs, action)
  end
  for lhs, fn in pairs(opts.raw or {}) do
    api.nvim_buf_set_keymap(buf, 'n', lhs, '', {
      nowait = true,
      silent = true,
      noremap = true,
      callback = function()
        fn(self_ref)
      end,
    })
  end
end

-- ---------------------------------------------------------------------------
-- Navigation / query editing

function M.ensure_visible(self)
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

--- Move one grid column left/right (wrap), mirroring the Lua port.
--- `refresh` names the method that re-lists the picker ('rerank' for the
--- filesystem picker, 'refresh' for the list picker).
function M.column_nav(self, delta, refresh)
  if self.single or self:one_line() then
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
  self:ensure_visible()
  self[refresh](self)
end

--- Shared half of the key dispatcher: cursor movement and query editing.
--- Returns true when the action was consumed. `refresh` names the re-list
--- method; `hooks.query_refresh` (optional) overrides it for query edits
--- (debounced typing); `hooks.on_char` (optional) runs for a single typed
--- character before it is appended and may consume it (`/` in the filesystem
--- picker); `hooks.on_query` (optional) runs after a query change and may
--- consume the rerank (the filesystem picker restarts its backend when the
--- dotfile mode flips).
function M.handle_common(self, action, refresh, hooks)
  hooks = hooks or {}
  -- Query edits may use a debounced entry point (the filesystem picker waits
  -- for the typing pause before re-asking the backend); navigation always
  -- re-lists immediately.
  local query_refresh = hooks.query_refresh or refresh
  if action == 'toggle_one_line' then
    M.toggle_one_line(self, refresh)
    return true
  end  if action == 'colnext' or action == 'colprev' then
    M.column_nav(self, action == 'colnext' and 1 or -1, refresh)
    return true
  end
  if action == 'pagedown' or action == 'pageup' then
    local screen = self:screen_count()
    local delta = action == 'pagedown' and screen or -screen
    if self.total > 0 then
      self.selected = math.max(0, math.min(self.selected + delta, self.total - 1))
      self:ensure_visible()
      self[refresh](self)
    end
    return true
  end
  if action == 'first' or action == 'last' then
    if self.total > 0 then
      self.selected = action == 'first' and 0 or (self.total - 1)
      self:ensure_visible()
      self[refresh](self)
    end
    return true
  end
  if action == 'down' or action == 'up' then
    if self.total > 0 then
      self.selected = (self.selected + (action == 'down' and 1 or -1)) % self.total
      self:ensure_visible()
      self[refresh](self)
    end
    return true
  end
  if action == 'clear' or action == 'backspace' then
    if #self.query > 0 then
      if action == 'clear' then
        self.query = ''
      else
        self.query = self.query:sub(1, -2)
      end
      self.selected = 0
      self.offset = 0
      if hooks.on_query and hooks.on_query(self) then
        return true
      end
      self[query_refresh](self)
    end
    return true
  end
  if #action == 1 then
    if hooks.on_char and hooks.on_char(self, action) then
      return true
    end
    self.query = self.query .. action
    self.selected = 0
    self.offset = 0
    if hooks.on_query and hooks.on_query(self) then
      return true
    end
    self[query_refresh](self)
    return true
  end
  return false
end

-- ---------------------------------------------------------------------------
-- Teardown

--- Tear down the picker split, timer, backend job and preview. Idempotent;
--- returns true when it actually closed the picker.
function M.close(self)
  if self.closed then
    return false
  end
  self.closed = true
  -- `*_grp` holds the numeric group id; nvim_del_augroup_by_name wants the
  -- name and rejects a number ("Invalid 'name': Expected Lua string"), which
  -- pcall would swallow — a picker re-opened on navigation would then leave its
  -- global VimResized/WinResized autocmd behind for the rest of the session.
  if self.leave_grp then
    pcall(api.nvim_del_augroup_by_id, self.leave_grp)
    self.leave_grp = nil
  end
  if self.resize_grp then
    pcall(api.nvim_del_augroup_by_id, self.resize_grp)
    self.resize_grp = nil
  end
  if self.dead_grp then
    local grp = self.dead_grp
    self.dead_grp = nil
    -- Deleting the group that is running right now raises E936 (the external
    -- close path), so retry on the next tick instead of leaking the autocmds.
    if not pcall(api.nvim_del_augroup_by_id, grp) then
      vim.schedule(function()
        pcall(api.nvim_del_augroup_by_id, grp)
      end)
    end
  end
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
  end
  if self.close_preview then
    self:close_preview()
  end
  -- close the picker window first: deleting the buffer of a shown window can
  -- leave an empty shell behind, and closing the split restores the layout
  if self.win and api.nvim_win_is_valid(self.win) then
    pcall(api.nvim_win_close, self.win, true)
  end
  if self.buf and api.nvim_buf_is_valid(self.buf) then
    pcall(api.nvim_buf_delete, self.buf, { force = true })
  end
  -- Put the pre-picker window sizes back: closing the split makes nvim
  -- re-equalize the remaining windows, which would otherwise resize the user's
  -- layout every time the picker is used.
  if self.restore_cmd and self.restore_tab == api.nvim_get_current_tabpage() then
    pcall(vim.cmd, self.restore_cmd)
  end
  self.restore_cmd = nil
  self.restore_tab = nil
  if api.nvim_win_is_valid(self.orig_win) then
    pcall(api.nvim_set_current_win, self.orig_win)
  end
  return true
end

-- ---------------------------------------------------------------------------
-- Rendering helpers

--- Truncate `text` to at most `w` display columns (whole chars), returning
--- the text and its display width.
function M.fit(text, w)
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

--- Build a prompt-segment list. Returns an `add(text, group)` closure and the
--- segment list; each segment is {start_col, len, group}.
function M.prompt_segments()
  local segs = {}
  local col = 0
  local function add(text, group)
    if text and #text > 0 then
      segs[#segs + 1] = { col, #text, group, text }
      col = col + #text
    end
  end
  return add, segs
end

--- Concatenate a segment list into the plain text it paints. The segments keep
--- their own text, so the prompt line and the one-line mode render from one
--- source instead of two hand-kept copies of the same concatenation.
function M.segments_text(segs)
  local parts = {}
  for _, seg in ipairs(segs) do
    parts[#parts + 1] = seg[4]
  end
  return table.concat(parts)
end

--- Paint one prompt line from a `prompt_segments()` list into `ns`.
function M.paint_segments(self, ns, line, segs)
  for _, seg in ipairs(segs) do
    if seg[3] then
      api.nvim_buf_add_highlight(self.buf, ns, seg[3], line, seg[1], seg[1] + seg[2])
    end
  end
end

--- Paint the one-line mode: the picker's prompt segments plus the entries on
--- the single row. `tail` is either the text of the selected entry or a list of
--- `{ text = ..., selected = ... }` cells: the row then carries the selection
--- and the entries that follow it, so a one-row picker still shows the variants
--- on offer instead of hiding them behind the cursor. Only the selected cell
--- gets the bar, so the row still reads as "this is what Enter opens". An
--- overflowing line is cut from the right — the query, which is what the user
--- is typing, keeps its position.
function M.paint_one_line(self, ns, head_segs, tail)
  local w = self:width()
  local head = M.segments_text(head_segs)
  local sep = '  '
  local cells
  if type(tail) == 'table' then
    cells = tail
  else
    cells = { { text = tail or '', selected = true } }
  end
  local text = head .. sep
  local used = vim.fn.strdisplaywidth(text)
  local sel_from, sel_to = nil, nil
  for i, cell in ipairs(cells) do
    local body = cell.text or ''
    local room = w - used
    local width = vim.fn.strdisplaywidth(body)
    if width > room then
      -- The selected cell is always shown, cut to the room that is left; a
      -- following cell that does not fit whole ends the strip instead.
      if i > 1 or room <= 0 then
        break
      end
      body = M.fit(body, room)
      width = vim.fn.strdisplaywidth(body)
    end
    if width == 0 then
      break
    end
    local from = #text
    text = text .. body
    if cell.selected then
      sel_from, sel_to = from, from + #body
    end
    used = used + width
    if i < #cells and used + #sep < w then
      text = text .. sep
      used = used + #sep
    end
  end
  text = M.fit(text, w)
  api.nvim_buf_set_lines(self.buf, 0, -1, false, {
    text .. string.rep(' ', math.max(0, w - vim.fn.strdisplaywidth(text))),
  })
  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  for _, seg in ipairs(head_segs) do
    if seg[3] and seg[1] < #text then
      -- A cut line may end inside a segment: clamp instead of highlighting
      -- past the end of the buffer text.
      api.nvim_buf_add_highlight(
        self.buf,
        ns,
        seg[3],
        0,
        seg[1],
        math.min(seg[1] + seg[2], #text)
      )
    end
  end
  if sel_from and sel_to and sel_from < #text then
    api.nvim_buf_add_highlight(
      self.buf,
      ns,
      'LustyNativeSel',
      0,
      sel_from,
      math.min(sel_to, #text)
    )
  end
  return text
end

-- Methods a picker class can bind directly (same signature, no per-picker
-- callbacks). Everything else is wrapped by the class with its own re-list
-- entry point.
M.BOUND = {
  'one_line',
  'toggle_one_line',
  'width',
  'height',
  'list_rows',
  'chrome',
  'max_cols',
  'col_width',
  'screen_count',
  'open_window',
  'on_win_resized',
  'ensure_geometry',
  'ensure_visible',
}

--- Bind the directly-reusable methods on a picker class table.
function M.bind(cls)
  for _, name in ipairs(M.BOUND) do
    cls[name] = M[name]
  end
end

return M
