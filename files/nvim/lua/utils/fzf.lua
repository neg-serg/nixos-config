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

function M.smart_files()
  local ok = pcall(require('fzf-lua').git_files, { show_untracked = true })
  if not ok then require('fzf-lua').files() end
end

function M.turbo_find(opts)
  opts = opts or {}
  require('fzf-lua').files({
    cwd = opts.cwd or vim.fn.expand('%:p:h'),
    fd_opts = '-H --ignore-vcs -d 2 --strip-cwd-prefix --type f',
    previewer = false,
  })
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

function M.frecency()
  local ranked = require('utils.frecency').get_ranked()
  local entries = {}
  local curr = vim.api.nvim_buf_get_name(0)
  for _, item in ipairs(ranked) do
    if item.path ~= curr and vim.uv.fs_stat(item.path) then
      table.insert(entries, item.path)
    end
  end
  require('fzf-lua').fzf_exec(entries, {
    prompt = 'Frecency❯ ',
    previewer = false,
    winopts = { height = 0.25 },
    actions = require('fzf-lua').defaults.actions.files,
  })
end

return M
