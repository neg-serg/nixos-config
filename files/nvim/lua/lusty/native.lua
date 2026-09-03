-- Lusty-native picker shim.
--
-- Runs the standalone lusty-native binary (packages/lusty-native) in a
-- floating terminal instead of the in-nvim float table. The picker prints
-- ACTION<TAB>PATH on selection (edit/tabedit/split/vsplit) and exits; cancel
-- exits 1 with no output. The Lua port remains the fallback: set
-- g:LustyExplorerNative = 0 to force the old in-nvim explorer.

local M = {}

local TOKENS = { edit = 'edit', tabedit = 'tabedit', split = 'split', vsplit = 'vsplit' }

--- Parse picker output lines for the ACTION<TAB>PATH line (printed after the
--- picker leaves the alternate screen). Returns (action, path) or nil.
function M._find_selection(lines)
  for i = #lines, 1, -1 do
    local action, path = lines[i]:match('^(%a+)\t(.+)$')
    if action and TOKENS[action] then
      return action, path
    end
  end
  return nil
end

local function open_in_window(win, action, path)
  if vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_set_current_win, win)
  end
  vim.cmd.noautocmd(TOKENS[action] .. ' ' .. vim.fn.fnameescape(path))
end

--- Run the native picker at root (a directory). Non-blocking.
function M.run(root)
  if vim.fn.executable('lusty-native') ~= 1 then
    vim.notify(
      'lusty-native binary not found on PATH (pkgs.neg.lusty-native missing?)',
      vim.log.levels.ERROR
    )
    return
  end

  local depth = tonumber(vim.g.LustyExplorerSearchDepth) or 2
  local skip = vim.g.LustyExplorerSkipDirs
  if skip == nil or skip == '' then
    skip = 'pic,tmp'
  end
  local cmd = { 'lusty-native', root, '--depth', tostring(depth), '--skip', tostring(skip) }

  local editor_w, editor_h = vim.o.columns, vim.o.lines
  local width = math.max(40, math.floor(editor_w * 0.92))
  local height = math.max(12, math.floor(editor_h * 0.86))
  local row = math.max(0, math.floor((editor_h - height) / 2))
  local col = math.max(0, math.floor((editor_w - width) / 2))
  local orig_win = vim.api.nvim_get_current_win()

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
  })
  vim.wo[win].winhighlight = 'Normal:NormalFloat,FloatBorder:FloatBorder'

  -- Returns the job id (0 on failure) so tests can drive the picker.
  local job = vim.fn.termopen(cmd, {
    on_exit = function()
      vim.schedule(function()
        local ok, lines = pcall(vim.api.nvim_buf_get_lines, buf, 0, -1, false)
        local action, path
        if ok then
          action, path = M._find_selection(lines)
        end
        if vim.api.nvim_win_is_valid(win) then
          pcall(vim.api.nvim_win_close, win, true)
        end
        pcall(vim.api.nvim_buf_delete, buf, { force = true })
        if action and path then
          open_in_window(orig_win, action, path)
        end
      end)
    end,
  })
  -- Send keystrokes straight into the picker (like fzf): insert mode on a
  -- terminal buffer is terminal mode.
  vim.cmd('startinsert')
  return job
end

return M
