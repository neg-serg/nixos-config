-- Lusty-native picker: Rust backend (lusty-native serve) rendered as a normal
-- nvim floating window with real highlights. No terminal buffer involved, so
-- it renders reliably even when nvim itself runs inside a web xterm.
--
-- The Lua port remains the fallback: g:LustyExplorerNative = 0.
--
-- Backend protocol (plain lines, tab separated):
--   Q <from> <to> <query>   -> "N <total>" + "R <i> <kind> <label>\t<path>" rows + "E"
-- kind: d (dir) / f (file) / l (link)

local lsc = require('lusty.ls_colors')

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

--- RU (йцукен) layout to EN chars (physical keys under RU produce Cyrillic).
local RU2EN = {
  ['й'] = 'q', ['ц'] = 'w', ['у'] = 'e', ['к'] = 'r', ['е'] = 't',
  ['н'] = 'y', ['г'] = 'u', ['ш'] = 'i', ['щ'] = 'o', ['з'] = 'p',
  ['х'] = '[', ['ъ'] = ']', ['ф'] = 'a', ['ы'] = 's', ['в'] = 'd',
  ['а'] = 'f', ['п'] = 'g', ['р'] = 'h', ['о'] = 'j', ['л'] = 'k',
  ['д'] = 'l', ['ж'] = ';', ['э'] = "'", ['я'] = 'z', ['ч'] = 'x',
  ['с'] = 'c', ['м'] = 'v', ['и'] = 'b', ['т'] = 'n', ['ь'] = 'm',
  ['б'] = ',', ['ю'] = '.',
}

local function basename(label)
  return label:match('([^/]+)$') or label
end

local Picker = {}
Picker.__index = Picker

function Picker.new(root)
  local self = setmetatable({}, Picker)
  self.root = root
  self.query = ''
  self.selected = 0 -- ranked position
  self.offset = 0 -- top visible ranked position
  self.total = 0
  self.window = {} -- ranked pos (offset+1..) -> { i, kind, label, path }
  self.pending = nil
  self.outbuf = {}
  self.dirs = nil -- cached top-level dir names for '/' completion
  self.show_dots = false
  self.maxw = 12 -- widest label (chars) in the current ranked set
  self.closed = false
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
  if envr and envr >= 6 then
    return math.max(6, math.min(envr, vim.o.lines - 2))
  end
  -- compact: at most 12 rows total (list + prompt), pinned to the bottom
  local ratio = tonumber(vim.g.LustyExplorerMaxHeightRatio) or 0.4
  ratio = math.max(0.15, math.min(0.6, ratio))
  local h = math.floor(vim.o.lines * ratio)
  return math.max(6, math.min(12, h))
end

function Picker:list_rows()
  return math.max(1, self:height() - 2)
end

--- Max columns of the entry grid: choose a pitch that fits the float width
--- exactly (col_w + 2 separator), so rows never overflow or wrap.
function Picker:max_cols()
  local w = self:width()
  local rows = self:list_rows()
  local total = math.max(self.total, 1)
  local needed = math.max(1, math.ceil(total / rows))
  -- cap the width influence: one huge name must not force a single column
  local name_w = math.max(math.min(self.maxw or 12, 20), 1)
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

--- Number of positions covered by one screenful of the grid.
function Picker:screen_count()
  return self:list_rows() * self:max_cols()
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
    title = self:title_text(),
    title_pos = 'left',
  })
  api.nvim_buf_set_option(buf, 'buftype', 'nofile')
  api.nvim_buf_set_option(buf, 'swapfile', false)
  api.nvim_buf_set_option(buf, 'modifiable', true)
  api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')
  api.nvim_win_set_option(win, 'wrap', false)
  api.nvim_win_set_option(win, 'winhighlight', 'Normal:LustyNativeFloat')
  api.nvim_win_set_option(win, 'winblend', 0)
  local empty = {}
  for _ = 1, h do
    empty[#empty + 1] = ''
  end
  api.nvim_buf_set_lines(buf, 0, -1, false, empty)
  self.buf = buf
  self.win = win
  self:setup_keymaps()
  self:setup_input_events()
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
  -- Telescope-style: edit the query in insert mode on the prompt row, so
  -- plain letters are just text input and can never hit normal-mode
  -- operators/prefix timeouts. A normal-mode copy of the maps stays as a
  -- fallback if the user ever escapes insert (C-c).
  local function map_i(lhs, action)
    local opts = { nowait = true, silent = true, noremap = true }
    opts.callback = function()
      self_ref:handle(action)
    end
    api.nvim_buf_set_keymap(buf, 'i', lhs, '', opts)
  end
  map_i('<CR>', 'enter')
  map_i('<Tab>', 'enter')
  map_i('<C-n>', 'down')
  map_i('<Down>', 'down')
  map_i('<C-p>', 'up')
  map_i('<Up>', 'up')
  map_i('<C-f>', 'colnext')
  map_i('<C-b>', 'colprev')
  map_i('<PageDown>', 'pagedown')
  map_i('<PageUp>', 'pageup')
  map_i('<C-t>', 'open_tab')
  map_i('<C-o>', 'open_split')
  map_i('<C-v>', 'open_vsplit')
  map_i('<C-w>', 'updir')
  map_i('<C-u>', 'clear_line')
  map_i('<Esc>', 'cancel')
  map_i('<C-c>', 'cancel')
  map_i('<C-g>', 'cancel')
  -- '/' keeps the Lusty dir-jump behaviour; '.' reveals dots via the change
  -- handler. RU physical keys type their EN equivalent.
  map_i('/', 'slash')
  for ru, en in pairs(RU2EN) do
    api.nvim_buf_set_keymap(buf, 'i', ru, en, { nowait = true, silent = true, noremap = true })
  end
end

--- Compact root path shown in the float border title.
function Picker:title_text()
  local path = self.root
  local home = os.getenv('HOME') or ''
  if home ~= '' and path:sub(1, #home) == home then
    path = '~' .. path:sub(#home + 1)
  end
  if #path > 48 then
    path = '...' .. path:sub(-45)
  end
  return path
end

--- 0-based index of the editable prompt row (the last buffer line).
function Picker:prompt_row()
  return self:height() - 1
end

--- Live query: the prompt line of the buffer (insert edits land there).
function Picker:current_query()
  if self.buf and api.nvim_buf_is_valid(self.buf) then
    local rows = api.nvim_buf_get_lines(self.buf, self:prompt_row(), self:prompt_row() + 1, false)
    return rows[1] or ''
  end
  return self.query
end

--- Push self.query into the prompt line and park the cursor at its end
--- (used by actions that change the query programmatically).
function Picker:sync_query()
  local row = self:prompt_row()
  if not self.buf or not api.nvim_buf_is_valid(self.buf) then
    return
  end
  pcall(api.nvim_buf_set_lines, self.buf, row, row + 1, false, { self.query })
  pcall(api.nvim_win_set_cursor, self.win, { row + 1, #self.query })
end

--- Text changed while typing in insert mode: adopt the new query, reset the
--- selection and rerank (debounced). Dots mode restarts the backend when the
--- leading '.' appears or disappears.
function Picker:on_text_changed()
  if self.closed or not self.buf then
    return
  end
  local q = self:current_query()
  if q == self.query then
    return
  end
  self.query = q
  self.selected = 0
  self.offset = 0
  if self:maybe_toggle_dots() then
    return
  end
  self:schedule_rerank()
end

--- Input events: listen for edits of the prompt line.
function Picker:setup_input_events()
  local self_ref = self
  self.input_grp = api.nvim_create_augroup('LustyPickInput' .. self.buf, { clear = true })
  api.nvim_create_autocmd({ 'TextChangedI', 'TextChangedP' }, {
    group = self.input_grp,
    buffer = self.buf,
    callback = function()
      vim.schedule(function()
        self_ref:on_text_changed()
      end)
    end,
  })
end
function Picker:request(parts, handler)
  self.pending = handler
  self.outbuf = {}
  vim.fn.chansend(self.job, table.concat(parts, '\t') .. '\n')
end

function Picker:rerank()
  pf('rerank')
  self.query = self:current_query()
  local from = self.offset
  local to = self.offset + self:screen_count()
  self:request({ 'Q', tostring(from), tostring(to), self.query }, function(lines)
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
            label = label,
            path = path,
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
    vim.schedule(function()
      self:draw()
    end)
  end)
end

function Picker:draw()
  if self.closed or not api.nvim_buf_is_valid(self.buf) then
    return
  end
  pf('draw')
  local rows = self:list_rows()
  local cols = self:max_cols()
  local h = rows + 1 -- grid rows + one prompt line
  local col_w = self:col_width()
  local lines = {}
  local cells = {} -- { line, col, item, pos }
  for r = 1, rows do
    local bufparts = {}
    for c = 1, cols do
      -- row-major: fill left-to-right, then next row (original Lusty order)
      local pos = self.offset + (r - 1) * cols + (c - 1)
      local item = self.window[pos - self.offset + 1]
      if item then
        local label = item.label
        if item.kind == 'd' then
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
        text = text .. string.rep(' ', math.max(0, col_w - w))
        bufparts[c] = text
        cells[#cells + 1] = { line = r, col = c, item = item, pos = pos, label_w = w }
      end
    end
    lines[r] = table.concat(bufparts, '  ')
  end
  for i = 1, h - 1 do
    if not lines[i] then
      lines[i] = ''
    end
  end
  -- rows 0..h-2 are list + spacer; the last row is the editable prompt and
  -- is never rewritten here (typing owns it, cursor must not move)
  api.nvim_buf_set_lines(self.buf, 0, h - 1, false, lines)

  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  local sel_col0 = 0
  for _, cell in ipairs(cells) do
    local entry = {
      name = basename(cell.item.label),
      is_dir = cell.item.kind == 'd',
      is_link = cell.item.kind == 'l',
      path = cell.item.path,
    }
    local group = lsc.group_for(entry)
    local start_col = (cell.col - 1) * (col_w + 2)
    if cell.pos == self.selected then
      sel_col0 = start_col
    end
    if group then
      local len = cell.label_w
      if len > col_w - 1 then
        len = col_w - 1
      end
      api.nvim_buf_add_highlight(self.buf, ns, group, cell.line - 1, start_col, start_col + len)
    end
    -- approximate fuzzy-match highlight: underline the first plain
    -- case-insensitive occurrence of the query in the entry basename
    if cell.pos ~= self.selected then
      local q = self.query
      if q ~= '' and q:sub(1, 1) ~= '.' then
        local base = basename(cell.item.label)
        local s, e = base:lower():find(q:lower(), 1, true)
        if s and e then
          local lstart = #cell.item.label - #base
          api.nvim_buf_add_highlight(
            self.buf, ns, 'LustyNativeMatch', cell.line - 1,
            start_col + lstart + s - 1, start_col + lstart + e
          )
        end
      end
    end
  end
  if self.total > 0 then
    local sel_row = math.floor(self.selected / cols)
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', sel_row, sel_col0, sel_col0 + col_w - 1)
  end
  self:paint_prompt()
  pf('drawn')
end

--- The prompt row holds only the editable query; the count is painted as a
--- right-aligned-ish suffix after it.
function Picker:paint_prompt()
  local row = self:prompt_row()
  local q = self:current_query()
  api.nvim_buf_add_highlight(self.buf, ns, 'LustyPromptQuery', row, 0, math.max(0, #q))
  if self.total > 0 then
    local suffix = ' [' .. self.total .. ']'
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyPromptPath', row, #q + 1, #q + 1 + #suffix)
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
  if self.input_grp then
    pcall(api.nvim_del_augroup_by_name, self.input_grp)
    self.input_grp = nil
  end
  if self._timer then
    self._timer:stop()
    self._timer = nil
  end
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
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
    if #self.current_query() > 0 then
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:sync_query()
      if self:maybe_toggle_dots() then
        return
      end
      self:schedule_rerank()
    end
    return
  end
  if action == 'backspace' then
    if #self.current_query() > 0 then
      self.query = self.query:sub(1, -2)
      self.selected = 0
      self.offset = 0
      self:sync_query()
      if self:maybe_toggle_dots() then
        return
      end
      self:schedule_rerank()
    end
    return
  end
  if action == 'updir' then
    if #self.current_query() > 0 then
      -- first C-w clears the typed text (shell/vim word-delete feel)
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:sync_query()
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
  if action == 'slash' then
    self:slash_typed()
    return
  end
  if action == 'clear_line' then
    if self:current_query() ~= '' then
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:sync_query()
      if self:maybe_toggle_dots() then
        return
      end
      self:schedule_rerank()
    end
    return
  end
  -- typing (normal-mode fallback path): keep the prompt line in sync
  if #action == 1 then
    self.query = self.query .. action
    self.selected = 0
    self.offset = 0
    self:sync_query()
    if self:maybe_toggle_dots() then
      return
    end
    self:schedule_rerank()
  end
end

--- '/' pressed while editing in insert mode: same dir-jump semantics as
--- before, decided against the live buffer query.
function Picker:slash_typed()
  local q = self:current_query()
  if q == '' then
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
          dirs[#dirs + 1] = name
        end
      end
      self.dirs = dirs
      self:complete_slash(q)
    end)
    return
  end
  self:complete_slash(q)
end

--- Query starting with '.' reveals dotfiles: restart the backend with
--- --dots when the mode changes (returns true when it did).
function Picker:maybe_toggle_dots()
  local want = self.query:sub(1, 1) == '.'
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
          dirs[#dirs + 1] = name
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
  self:sync_query()
  self:rerank()
end

function Picker:restart(root)
  self:close() -- restores the caller window
  local np = Picker.new(root)
  np:startup()
  return np
end

function Picker:open_current(action)
  local rel = self.selected - self.offset
  local item = self.window[rel + 1]
  if not item then
    return
  end
  if item.kind == 'd' then
    self:restart(item.path)
    return
  end
  local cmds = { edit = 'edit', open_tab = 'tabedit', open_split = 'split', open_vsplit = 'vsplit' }
  local ex = action == 'enter' and 'edit' or cmds[action]
  if not ex then
    return
  end
  local win = api.nvim_get_current_win()
  local path = item.path
  self:close()
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_current_win, win)
  end
  vim.cmd(ex .. ' ' .. vim.fn.fnameescape(path))
end

function Picker:startup()
  if vim.fn.executable('lusty-native') ~= 1 then
    vim.notify('lusty-native binary not found on PATH', vim.log.levels.ERROR)
    return
  end
  self:open_window()
  -- telescope-style: edit the query on the prompt row in insert mode
  pcall(api.nvim_win_set_cursor, self.win, { self:prompt_row() + 1, 0 })
  vim.cmd('startinsert')
  self:start_backend()
end

function Picker:start_backend()
  local depth = tonumber(vim.g.LustyExplorerSearchDepth) or 2
  local skip = vim.g.LustyExplorerSkipDirs
  if skip == nil or skip == '' then
    skip = 'pic,tmp'
  end
  local cmd = { 'lusty-native', 'serve', self.root, '--depth', tostring(depth), '--skip', skip }
  if self.show_dots then
    cmd[#cmd + 1] = '--dots'
  end
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
  end
  local self_ref = self
  local acc = ''
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
        if line == 'E' then
          if self_ref.pending then
            local handler = self_ref.pending
            self_ref.pending = nil
            local out = self_ref.outbuf
            self_ref.outbuf = {}
            pf('resp')
            handler(out)
          end
        elseif self_ref.pending then
          self_ref.outbuf[#self_ref.outbuf + 1] = line
        end
      end
    end,
  })
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
  api.nvim_set_hl(0, 'LustyPromptQuery', { fg = '#ffffff' })
  api.nvim_set_hl(0, 'LustyNativeMatch', { underline = true })
  -- nearly-black but not #000000: the web/xterm layer treats exact black as
  -- the transparent default, while #0c0d14 rendered too gray on this setup
  api.nvim_set_hl(0, 'LustyNativeFloat', { bg = '#000001', fg = '#d4d4d4' })
  -- omp.zsh path segment colors (neg.omp.json)
  api.nvim_set_hl(0, 'LustyPromptTilde', { fg = '#287373' })
  api.nvim_set_hl(0, 'LustyPromptSep', { fg = '#005faf' })
  api.nvim_set_hl(0, 'LustyPromptPath', { fg = '#95a7bc' })
end

M.ensure_highlights()

return M
