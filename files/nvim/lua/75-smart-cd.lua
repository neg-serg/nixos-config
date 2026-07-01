local M = {}
local nav  -- lazy-loaded below

-- Smart directory changing function: toggle between project root and file dir
function M.smart_cd()
  local file_path = vim.fn.expand('%:p')
  local current_dir = vim.fn.getcwd()

  if file_path == "" then
    print("No file in buffer - using current dir: " .. current_dir)
    return
  end

  nav = nav or require('utils.nav')
  local file_dir = vim.fn.expand('%:p:h')
  local project_root = nav.project_root(file_dir)

  local target_dir = current_dir
  local reason = ""

  if project_root then
    if not string.find(current_dir, project_root, 1, true) then
      target_dir = project_root
      reason = "project root"
    else
      target_dir = file_dir
      reason = "file directory (inside project)"
    end
  else
    target_dir = file_dir
    reason = "file directory (no project found)"
  end

  if target_dir == current_dir then
    print("Already in correct directory: " .. target_dir)
    return
  end

  vim.cmd('cd ' .. vim.fn.fnameescape(target_dir))
  print("Changed directory to " .. reason .. ": " .. target_dir)

  if package.loaded['heirline'] then
    vim.cmd('redrawstatus')
  end
end

return M
