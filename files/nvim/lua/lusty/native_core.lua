-- Shared core of the native Lusty pickers: the filesystem float
-- (`lusty.native`, Rust backend) and the generic list float
-- (`lusty.native_pick`, Lua source). Both render the same bottom-anchored
-- rounded float with the same geometry, colours and key handling, so the
-- common half lives here; each picker only supplies the parts that differ
-- (long view vs item groups, backend job vs Lua source).
--
-- The module is a stateless method bag: functions take the picker as their
-- first argument, so a picker class either binds the shared methods with
-- `core.bind(cls)` or wraps them with its own re-list method.

local api = vim.api

-- RU (йцукен) layout to EN chars, shared with the other pickers.
local RU2EN = require('lusty.ru2en')

local M = {}

-- ---------------------------------------------------------------------------
-- Geometry

function M.width(self)
  local envw = tonumber(os.getenv('LUSTY_WIDTH'))
  if envw and envw >= 60 then
    return math.max(60, math.min(envw, vim.o.columns - 4))
  end
  local ratio = tonumber(vim.g.LustyExplorerWidthRatio) or 0.8
  ratio = math.max(0.5, math.min(0.98, ratio))
  return math.max(60, math.floor(vim.o.columns * ratio))
end

function M.height(self)
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

function M.list_rows(self)
  -- Entry rows inside the window: everything but the prompt line, so the grid
  -- fills the window instead of leaving its last row empty.
  return math.max(1, self:height() - 1)
end

--- Max columns of the entry grid: choose a pitch that fits the float width
--- exactly (col_w + 2 separator), so rows never overflow or wrap.
function M.max_cols(self)
  if self.long or self.single then
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

function M.col_width(self)
  local cols = self:max_cols()
  local w = self:width()
  -- remaining width for the text columns after the separators
  local text_w = w - 2 * (cols - 1)
  return math.max(6, math.floor(text_w / cols))
end

--- Number of positions covered by one screenful of the grid.
function M.screen_count(self)
  return self:list_rows() * self:max_cols()
end

-- ---------------------------------------------------------------------------
-- Window

function M.open_window(self)
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

-- ---------------------------------------------------------------------------
-- Keymaps

--- Special keys every picker binds to the same action. Printable ASCII and the
--- RU layout aliases are added separately; per-picker keys go through
--- `opts.actions` (lhs -> action, overrides the base) and `opts.raw`
--- (lhs -> function(self), caller-supplied raw callbacks).
local BASE_KEYS = {
  { '<Tab>', 'enter' },
  { '<CR>', 'enter' },
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
--- filesystem float, 'refresh' for the list float).
function M.column_nav(self, delta, refresh)
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
  self:ensure_visible()
  self[refresh](self)
end

--- Shared half of the key dispatcher: cursor movement and query editing.
--- Returns true when the action was consumed. `refresh` names the re-list
--- method; `hooks.query_refresh` (optional) overrides it for query edits
--- (debounced typing); `hooks.on_char` (optional) runs for a single typed
--- character before it is appended and may consume it (`/` in the filesystem
--- float); `hooks.on_query` (optional) runs after a query change and may
--- consume the rerank (the filesystem float restarts its backend when the
--- dotfile mode flips).
function M.handle_common(self, action, refresh, hooks)
  hooks = hooks or {}
  -- Query edits may use a debounced entry point (the filesystem float waits
  -- for the typing pause before re-asking the backend); navigation always
  -- re-lists immediately.
  local query_refresh = hooks.query_refresh or refresh
  if action == 'colnext' or action == 'colprev' then
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

--- Tear down the float, timer, backend job and preview. Idempotent; returns
--- true when it actually closed the picker.
function M.close(self)
  if self.closed then
    return false
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
  if self.close_preview then
    self:close_preview()
  end
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
      segs[#segs + 1] = { col, #text, group }
      col = col + #text
    end
  end
  return add, segs
end

--- Paint one prompt line from a `prompt_segments()` list into `ns`.
function M.paint_segments(self, ns, line, segs)
  for _, seg in ipairs(segs) do
    if seg[3] then
      api.nvim_buf_add_highlight(self.buf, ns, seg[3], line, seg[1], seg[1] + seg[2])
    end
  end
end

-- Methods a picker class can bind directly (same signature, no per-picker
-- callbacks). Everything else is wrapped by the class with its own re-list
-- entry point.
M.BOUND = {
  'width',
  'height',
  'list_rows',
  'max_cols',
  'col_width',
  'screen_count',
  'open_window',
  'ensure_visible',
}

--- Bind the directly-reusable methods on a picker class table.
function M.bind(cls)
  for _, name in ipairs(M.BOUND) do
    cls[name] = M[name]
  end
end

return M
