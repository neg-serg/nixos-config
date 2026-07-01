-- ── :Redir — capture command/shell output in scratch buffer ──────────
vim.api.nvim_create_user_command('Redir', function(opts)
  -- Close any existing scratch windows
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.w[win].scratch then
      vim.api.nvim_win_close(win, true)
    end
  end

  local lines
  local cmd = opts.args

  if cmd:sub(1, 1) == '!' then
    -- Shell command
    local shell_cmd = cmd:sub(2)
    if shell_cmd:find(' %%') then
      shell_cmd = shell_cmd:gsub(' %%', ' ' .. vim.fn.expand('%:p'))
    end
    if opts.range == 0 then
      lines = vim.fn.systemlist(shell_cmd)
    else
      local range_lines = vim.api.nvim_buf_get_lines(0, opts.line1 - 1, opts.line2, false)
      local input = table.concat(range_lines, '\n')
      lines = vim.fn.systemlist(shell_cmd, input)
    end
  else
    -- Vim command — capture output
    local ok, result = pcall(vim.api.nvim_exec2, cmd, { output = true })
    if ok and result.output then
      lines = vim.split(result.output, '\n', { plain = true })
    else
      lines = { 'Error: ' .. tostring(result) }
    end
  end

  vim.cmd('vnew')
  vim.w.scratch = true
  vim.bo.buftype = 'nofile'
  vim.bo.bufhidden = 'wipe'
  vim.bo.buflisted = false
  vim.bo.swapfile = false
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines or {})
end, { nargs = 1, complete = 'command', bar = true, range = true })

-- ── Paste commands ──────────────────────────────────────────────────
vim.api.nvim_create_user_command('IX', function(opts)
  vim.cmd(opts.line1 .. ',' .. opts.line2 .. "w !curl -fsSL -F 'f:1=<-' ix.io | tr -d ' ' | wl-copy")
end, { range = '%' })

vim.api.nvim_create_user_command('TB', function(opts)
  vim.cmd(opts.line1 .. ',' .. opts.line2 .. "w !nc termbin.com 9999 | tr -d ' ' | wl-copy")
end, { range = '%' })

vim.api.nvim_create_user_command('ZP', function(opts)
  vim.cmd(opts.line1 .. ',' .. opts.line2 .. "w !curl -fsSL -F 'file=@-' https://0x0.st | tr -d ' ' | wl-copy")
end, { range = '%' })
