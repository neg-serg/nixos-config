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
  return self
end

function Picker:width()
  local ratio = tonumber(vim.g.LustyExplorerWidthRatio) or 0.8
  ratio = math.max(0.5, math.min(0.98, ratio))
  return math.max(60, math.floor(vim.o.columns * ratio))
end

function Picker:height()
  local ratio = tonumber(vim.g.LustyExplorerMaxHeightRatio) or 0.5
  ratio = math.max(0.2, math.min(0.9, ratio))
  return math.max(8, math.min(24, math.floor(vim.o.lines * ratio)))
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
  map('<C-w>', 'updir')
  map('<C-n>', 'down')
  map('<C-p>', 'up')
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
  map('<C-u>', 'clear')
  map('<C-t>', 'open_tab')
  map('<C-o>', 'open_split')
  map('<C-v>', 'open_vsplit')
  map('<Esc>', 'cancel')
  map('<C-c>', 'cancel')
  map('<C-g>', 'cancel')
end

function Picker:request(parts, handler)
  self.pending = handler
  self.outbuf = {}
  vim.fn.chansend(self.job, table.concat(parts, '\t') .. '\n')
end

function Picker:rerank()
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
  for i = 1, h do
    if not lines[i] then
      lines[i] = ''
    end
  end
  lines[h] = self:prompt_text()
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

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
  end
  if self.total > 0 then
    local sel_row = math.floor(self.selected / cols)
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', sel_row, sel_col0, sel_col0 + col_w - 1)
  end
  self:paint_prompt(h)
end

--- Bottom prompt: current path with Lusty prompt colors, then > query.
function Picker:prompt_text()
  local path = self.root
  local home = os.getenv('HOME') or ''
  if home ~= '' and path:sub(1, #home) == home then
    path = '~' .. path:sub(#home + 1)
  end
  return path .. ' \u{f105} ' .. self.query
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

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
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
    if #self.query > 0 then
      self.query = ''
      self.selected = 0
      self.offset = 0
      if self:maybe_toggle_dots() then
        return
      end
      self:rerank()
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
      self:rerank()
    end
    return
  end
  if action == 'updir' then
    if #self.query > 0 then
      -- first C-w clears the typed text (shell/vim word-delete feel)
      self.query = ''
      self.selected = 0
      self.offset = 0
      self:rerank()
      return
    end
    local parent = self.root:match('^(.*)/[^/]+$')
    if parent and parent ~= '' then
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
    self:rerank()
  end
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
