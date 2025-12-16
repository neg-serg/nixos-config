-- Enhanced Markdown link navigation and URL handling
-- Ported from the legacy home overlay before the Home Manager merge.

local uv = vim.uv or vim.loop

local function open_url(url)
  if url:match('^https?://') or url:match('^file://') then
    local cmd
    if vim.fn.has('mac') == 1 then
      cmd = { 'open', url }
    elseif vim.fn.has('wsl') == 1 then
      cmd = { 'wslview', url }
    else
      cmd = { 'xdg-open', url }
    end
    vim.fn.jobstart(cmd, { detach = true })
  end
end

local function goto_markdown_anchor(anchor)
  if not anchor or anchor == '' then return end
  local target = anchor
  target = target:gsub('[%p%c%s]', ' '):gsub('%s+', ' '):gsub('^%s+', ''):gsub('%s+$', ''):lower()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  for i, l in ipairs(lines) do
    local text = l:gsub('^#+%s*', ''):gsub('^%s+', ''):gsub('%s+$', ''):lower()
    text = text:gsub('[%p%c%s]', ' '):gsub('%s+', ' ')
    if text == target then
      vim.api.nvim_win_set_cursor(0, { i, 0 })
      return true
    end
  end
end

local preferred_dirs = { 'notes', 'docs', 'wiki' }

local function link_at_cursor()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_get_current_line()
  local c = col + 1

  do
    local i = 1
    while true do
      local s, e, inner = line:find('%[%[([^%]]+)%]%]', i)
      if not s then break end
      if c >= s and c <= e then
        local target = inner
        local pipe = target:find('|')
        if pipe then target = target:sub(1, pipe - 1) end
        local anchor
        local hash = target:find('#')
        if hash then
          anchor = target:sub(hash + 1)
          target = target:sub(1, hash - 1)
        end
        target = vim.trim(target)
        if target == '' then return { type = 'heading', anchor = anchor } end
        return { type = 'file', path = target, anchor = anchor }
      end
      i = e + 1
    end
  end

  do
    local i = 1
    while true do
      local s, e, text, url = line:find('%[([^%]]-)%]%(([^%)]-)%)', i)
      if not s then break end
      if c >= s and c <= e then
        if url:match('^https?://') then
          return { type = 'url', url = url }
        end
        if url:match('^file://') then url = url:gsub('^file://', '') end
        local anchor
        local hash = url:find('#')
        if hash then anchor = url:sub(hash + 1); url = url:sub(1, hash - 1) end
        url = vim.trim(url)
        if url == '' then return { type = 'heading', anchor = anchor } end
        return { type = 'file', path = url, anchor = anchor }
      end
      i = e + 1
    end
  end

  do
    local i = 1
    while true do
      local s, e, url = line:find('%<((https?://)[^%s>]+)%>', i)
      if not s then break end
      if c >= s and c <= e then return { type = 'url', url = url } end
      i = e + 1
    end
  end

  do
    local i = 1
    while true do
      local s, e, url = line:find('(https?://%S+)', i)
      if not s then break end
      if c >= s and c <= e then return { type = 'url', url = url } end
      i = e + 1
    end
  end

  return nil
end

local function open_link(opts)
  opts = opts or {}
  local link = link_at_cursor()
  if not link then return vim.cmd([[normal! gf]]) end
  if link.type == 'url' then
    return open_url(link.url)
  elseif link.type == 'heading' then
    goto_markdown_anchor(link.anchor); return
  elseif link.type == 'file' then
    local path = link.path
    do
      local has_slash = path:find('/') ~= nil
      local has_ext = path:match('%.[%w%.]+$') ~= nil
      local candidates = {}
      if not has_slash then
        for _, d in ipairs(preferred_dirs) do
          table.insert(candidates, d .. '/' .. path)
          if not has_ext then
            table.insert(candidates, d .. '/' .. path .. '.md')
            table.insert(candidates, d .. '/' .. path .. '.mdx')
          end
        end
      end
      for _, c in ipairs(candidates) do
        local stat_ok = false
        if uv and uv.fs_stat then stat_ok = uv.fs_stat(c) ~= nil
        else stat_ok = vim.fn.filereadable(c) == 1 or vim.fn.isdirectory(c) == 1 end
        if stat_ok then
          vim.cmd.edit(vim.fn.fnameescape(c))
          if opts.jump_to_anchor and link.anchor then goto_markdown_anchor(link.anchor) end
          return
        end
      end
    end
    if path == nil or path == '' then return end
    vim.cmd(('find %s'):format(vim.fn.fnameescape(path)))
    if opts.jump_to_anchor and link.anchor then goto_markdown_anchor(link.anchor) end
    return
  end
end

vim.keymap.set('n', 'gf', function() open_link({ jump_to_anchor = false }) end,
  { buffer = true, desc = 'Open file/wiki/URL under cursor' })
vim.keymap.set('n', 'gF', function() open_link({ jump_to_anchor = true }) end,
  { buffer = true, desc = 'Open and jump to anchor' })
vim.keymap.set('n', 'gx', function()
  local link = link_at_cursor()
  if link and link.type == 'url' then open_url(link.url)
  else pcall(vim.cmd.normal, { args = { 'gx' }, bang = true }) end
end, { buffer = true, desc = 'Open URL under cursor' })
