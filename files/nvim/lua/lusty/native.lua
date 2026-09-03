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
  self.closed = false
  self.orig_win = api.nvim_get_current_win()
  return self
end

function Picker:width()
  local ratio = tonumber(vim.g.LustyExplorerWidthRatio) or 0.6
  return math.max(40, math.floor(vim.o.columns * math.min(0.92, ratio + 0.32)))
end

function Picker:height()
  local ratio = tonumber(vim.g.LustyExplorerMaxHeightRatio) or 0.8
  return math.max(10, math.floor(vim.o.lines * math.min(0.9, ratio)))
end

function Picker:list_rows()
  return math.max(1, self:height() - 3)
end

function Picker:open_window()
  local w, h = self:width(), self:height()
  local row = math.max(0, math.floor((vim.o.lines - h) / 2))
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
  api.nvim_buf_set_lines(buf, 0, -1, false, {})
  self.buf = buf
  self.win = win
  self:setup_keymaps()
end

function Picker:setup_keymaps()
  local buf = self.buf
  local self_ref = self
  local function map(lhs, action)
    local opts = { nowait = true, silent = true, noremap = true, buffer = buf }
    opts.callback = function()
      self_ref:handle(action)
    end
    pcall(api.nvim_buf_set_keymap, buf, 'n', lhs, '', opts)
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
  map('<C-f>', 'pagedown')
  map('<C-b>', 'pageup')
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
  local rows = self:list_rows()
  local from = self.offset
  local to = self.offset + rows
  self:request({ 'Q', tostring(from), tostring(to), self.query }, function(lines)
    local win_rows = {}
    local total = self.total
    for _, ln in ipairs(lines) do
      local n = ln:match('^N (%d+)$')
      if n then
        total = tonumber(n)
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
  local h = rows + 3
  local lines = {}
  local meta = {} -- buffer line -> row info
  -- status line
  lines[1] = self.root .. '  (' .. self.total .. ')'
  for r = 1, rows do
    local item = self.window[r]
    if item then
      local label = item.label
      if item.kind == 'd' then
        label = label .. '/'
      end
      lines[1 + r] = label
      meta[1 + r] = item
    else
      lines[1 + r] = ''
    end
  end
  -- prompt line at the bottom
  lines[h] = '>> ' .. self.query
  api.nvim_buf_set_lines(self.buf, 0, -1, false, lines)

  api.nvim_buf_clear_namespace(self.buf, ns, 0, -1)
  -- status: dim
  api.nvim_buf_add_highlight(self.buf, ns, 'Comment', 0, 0, -1)
  for line_no, item in pairs(meta) do
    local entry = {
      name = basename(item.label),
      is_dir = item.kind == 'd',
      is_link = item.kind == 'l',
      path = item.path,
    }
    local group = lsc.group_for(entry)
    if group then
      api.nvim_buf_add_highlight(self.buf, ns, group, line_no - 1, 0, -1)
    end
  end
  -- selection marker
  local sel_line = 1 + (self.selected - self.offset) + 1
  if meta[sel_line - 1] then
    api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativeSel', sel_line - 1, 0, -1)
  end
  api.nvim_buf_add_highlight(self.buf, ns, 'LustyNativePrompt', h - 1, 3, -1)
end

function Picker:ensure_visible()
  local rows = self:list_rows()
  if self.selected < self.offset then
    self.offset = self.selected
  elseif self.selected >= self.offset + rows then
    self.offset = self.selected - rows + 1
  end
  self.offset = math.max(0, self.offset)
end

function Picker:close()
  if self.closed then
    return
  end
  self.closed = true
  if self.job and vim.fn.jobwait({ self.job }, 0)[1] == -1 then
    vim.fn.jobstop(self.job)
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
  if action == 'pagedown' or action == 'pageup' then
    local rows = self:list_rows()
    local delta = action == 'pagedown' and rows or -rows
    if self.total > 0 then
      self.selected = math.max(0, math.min(self.selected + delta, self.total - 1))
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
      self:rerank()
    end
    return
  end
  if action == 'backspace' then
    if #self.query > 0 then
      self.query = self.query:sub(1, -2)
      self.selected = 0
      self.offset = 0
      self:rerank()
    end
    return
  end
  if action == 'updir' then
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
  if #ch == 1 then
    self.query = self.query .. ch
    self.selected = 0
    self.offset = 0
    self:rerank()
  end
end

function Picker:restart(root)
  local win = api.nvim_get_current_win()
  self:close()
  local np = Picker.new(root)
  np.query = ''
  api.nvim_set_current_win(win)
  np:startup()
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
  local win = api.nvim_get_current_win()
  self:close()
  if api.nvim_win_is_valid(win) then
    pcall(api.nvim_set_current_win, win)
  end
  vim.cmd.noautocmd(cmds[action] .. ' ' .. vim.fn.fnameescape(item.path))
end

function Picker:startup()
  if vim.fn.executable('lusty-native') ~= 1 then
    vim.notify('lusty-native binary not found on PATH', vim.log.levels.ERROR)
    return
  end
  local depth = tonumber(vim.g.LustyExplorerSearchDepth) or 2
  local skip = vim.g.LustyExplorerSkipDirs
  if skip == nil or skip == '' then
    skip = 'pic,tmp'
  end
  self:open_window()
  local cmd = { 'lusty-native', 'serve', self.root, '--depth', tostring(depth), '--skip', skip }
  local self_ref = self
  local acc = ''
  self.job = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if self_ref.closed then
        return
      end
      acc = acc .. table.concat(data, '')
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
  local ok = pcall(api.nvim_set_hl, 0, 'LustyNativeSel', { bg = '#3d3d3d' })
  if not ok then
    api.nvim_set_hl(0, 'LustyNativeSel', { bg = 'Gray' })
  end
  api.nvim_set_hl(0, 'LustyNativePrompt', { fg = '#95a7bc', bold = true })
end

M.ensure_highlights()

return M
