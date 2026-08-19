-- fff-based picker helpers (fff replaced fzf-lua as the file finder).
local M = {}

M.ignore_patterns = {
  '__pycache__/', '__pycache__/*',
  'build/', 'gradle/', 'node_modules/', 'node_modules/*',
  'smalljre_*/*', 'target/', 'vendor/*',
  '.dart_tool/', '.git/', '.github/', '.gradle/', '.idea/', '.vscode/',
  '%.sqlite3', '%.ipynb', '%.lock', '%.pdb', '%.dll', '%.class', '%.exe',
  '%.cache', '%.pdf', '%.dylib', '%.jar', '%.docx', '%.met', '%.burp',
  '%.mp4', '%.mkv', '%.rar', '%.zip', '%.7z', '%.tar', '%.bz2', '%.epub',
  '%.flac', '%.tar.gz',
}

function M.project_root()
  return require('utils.nav').project_root(vim.uv.cwd())
end

function M.qf_toggle()
  local winid = vim.fn.getqflist({ winid = 0 }).winid
  if winid ~= 0 then vim.cmd('cclose') else vim.cmd('copen') end
end

function M.qf_clear()
  vim.fn.setqflist({})
  vim.notify('Quickfix cleared')
end

function M.apply_cmd_to_qf(cmd)
  if not cmd or cmd == '' then return end
  vim.cmd('copen')
  vim.cmd('cdo ' .. cmd)
end

return M
