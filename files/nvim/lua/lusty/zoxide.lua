-- Push locations opened via the Lusty pickers into the zoxide database so
-- the shell z/zi and the Snacks zoxide picker keep up with where files were
-- actually opened. zoxide stores directories only: opening a file adds its
-- parent, entering/opening a directory adds the directory itself.

local M = {}

--- Add the location of `path` (file -> parent dir, dir -> itself).
--- Detached and fire-and-forget: never blocks the picker, never errors.
function M.add(path)
  if vim.fn.executable('zoxide') ~= 1 then
    return
  end
  if type(path) ~= 'string' or path == '' then
    return
  end
  local dir = path
  if vim.fn.isdirectory(path) ~= 1 then
    dir = vim.fn.fnamemodify(path, ':h')
  end
  if dir == '' or vim.fn.isdirectory(dir) ~= 1 then
    return
  end
  vim.system({ 'zoxide', 'add', dir }, { detach = true })
end

return M
