
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

function M.best_find_cmd()
  if vim.fn.executable('fd') == 1 then
    return { 'fd', '-H', '--ignore-vcs', '--strip-cwd-prefix' }
  else
    return { 'rg', '--files', '--hidden', '--iglob', '!.git' }
  end
end

function M.project_root()
  local cwd = vim.loop.cwd()
  for _, marker in ipairs({ '.git', '.hg', 'pyproject.toml', 'package.json', 'Cargo.toml', 'go.mod' }) do
    local p = vim.fn.finddir(marker, cwd .. ';'); if p ~= '' then return vim.fn.fnamemodify(p, ':h') end
    p = vim.fn.findfile(marker, cwd .. ';'); if p ~= '' then return vim.fn.fnamemodify(p, ':h') end
  end
  return cwd
end

function M.safe_buffer_previewer_maker(filepath, bufnr, opts)
  local max_bytes = 1.5 * 1024 * 1024
  local stat = vim.loop.fs_stat(filepath)
  if stat and stat.size and stat.size > max_bytes then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '<< file too large to preview >>' }); return
  end
  if filepath:match('%.(png|jpe?g|gif|webp|pdf|zip|7z|rar)$') then
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { '<< binary file >>' }); return
  end
  return require('telescope.previewers').buffer_previewer_maker(filepath, bufnr, opts)
end

-- Deep create: mkdir -p and create empty file
function M.fb_create_deep(prompt_bufnr)
  local fb = require('telescope').extensions.file_browser
  local actions = fb.actions
  local state = require('telescope.actions.state')
  local picker = state.get_current_picker(prompt_bufnr)
  local cwd = (picker and picker._cwd) or vim.loop.cwd()
  vim.ui.input({ prompt = 'New path (relative): ' }, function(input)
    if not input or input == '' then return end
    local abs = vim.fs.normalize(cwd .. '/' .. input)
    vim.fn.mkdir(vim.fn.fnamemodify(abs, ':h'), 'p')
    if vim.fn.filereadable(abs) == 0 then vim.fn.writefile({}, abs) end
    actions.refresh(prompt_bufnr)
    vim.cmd.edit(abs)
  end)
end

-- Duplicate selected file
function M.fb_duplicate(prompt_bufnr)
  local e = require('telescope.actions.state').get_selected_entry(); if not e or not e.path then return end
  local src = e.path
  local default = src .. '.copy'
  vim.ui.input({ prompt = 'Duplicate to: ', default = default }, function(dst)
    if not dst or dst == '' then return end
    vim.fn.mkdir(vim.fn.fnamemodify(dst, ':h'), 'p')
    vim.fn.writefile(vim.fn.readfile(src, 'b'), dst, 'b')
    require('telescope').extensions.file_browser.actions.refresh(prompt_bufnr)
    vim.notify('Duplicated → ' .. dst)
  end)
end

-- Diff two selected files (multi-select with <Tab>)
function M.fb_diff_two()
  local st = require('telescope.actions.state')
  local pick = st.get_current_picker(0)
  local sels = pick and pick:get_multi_selection() or {}
  if #sels < 2 then return vim.notify('Select two files (use <Tab>)', vim.log.levels.WARN) end
  local a = sels[1].path or sels[1].value
  local b = sels[2].path or sels[2].value
  vim.cmd('tabnew')
  vim.cmd('edit ' .. vim.fn.fnameescape(a))
  vim.cmd('vert diffsplit ' .. vim.fn.fnameescape(b))
end

-- Diff against HEAD (uses fugitive if present, else fallback)
function M.fb_diff_head()
  local e = require('telescope.actions.state').get_selected_entry(); if not e or not e.path then return end
  local file = e.path
  if vim.fn.exists(':Gvdiffsplit') == 2 then
    vim.cmd('Gvdiffsplit ' .. vim.fn.fnameescape(file))
    return
  end
  local root = M.project_root()
  local rel = file:gsub('^' .. vim.pesc(root) .. '/?', '')
  local lines = vim.fn.systemlist({ 'git', '-C', root, 'show', 'HEAD:' .. rel })
  if vim.v.shell_error ~= 0 then return vim.notify('Not in git or file not tracked at HEAD', vim.log.levels.WARN) end
  vim.cmd('tabnew')
  local head_buf = vim.api.nvim_get_current_buf()
  vim.api.nvim_buf_set_option(head_buf, 'buftype', 'nofile')
  vim.api.nvim_buf_set_option(head_buf, 'bufhidden', 'wipe')
  vim.api.nvim_buf_set_name(head_buf, 'HEAD:' .. rel)
  vim.api.nvim_buf_set_lines(head_buf, 0, -1, false, lines)
  vim.cmd('vert diffsplit ' .. vim.fn.fnameescape(file))
end

function M.apply_cmd_to_qf(cmd)
  if not cmd or cmd == '' then return end
  vim.cmd('copen')
  vim.cmd('cdo ' .. cmd)
end

function M.qf_toggle()
  local winid = vim.fn.getqflist({ winid = 0 }).winid
  if winid ~= 0 then vim.cmd('cclose') else vim.cmd('copen') end
end

function M.qf_clear()
  vim.fn.setqflist({})
  vim.notify('Quickfix cleared')
end

function M.qf_picker()
  local pickers = require('telescope.pickers')
  local finders = require('telescope.finders')
  local conf = require('telescope.config').values
  local actions = require('telescope.actions')
  local state = require('telescope.actions.state')

  local qf = vim.fn.getqflist({ items = 1 }).items or {}
  if #qf == 0 then return vim.notify('Quickfix is empty') end

  pickers.new({}, {
    prompt_title = 'Quickfix',
    finder = finders.new_table({
      results = qf,
      entry_maker = function(item)
        local bufname = (item.bufnr and vim.api.nvim_buf_is_valid(item.bufnr)) and vim.api.nvim_buf_get_name(item.bufnr) or item.filename or ''
        local disp = (bufname ~= '' and (vim.fn.fnamemodify(bufname, ':.')) or '[No Name]') ..
                     ':' .. (item.lnum or 0) .. ':' .. (item.col or 0) .. '  ' .. (item.text or '')
        return {
          value = item,
          display = disp,
          ordinal = disp,
          path = bufname,
          lnum = item.lnum, col = item.col,
        }
      end
    }),
    sorter = conf.generic_sorter({}),
    previewer = conf.qflist_previewer({}),
    attach_mappings = function(bufnr, map)
      -- open (default <CR> already works)
      -- delete current selection(s) from qf
      local function delete_selected()
        local picker = state.get_current_picker(bufnr)
        local sels = picker:get_multi_selection()
        if #sels == 0 then
          local cur = state.get_selected_entry(bufnr); if cur then sels = { cur } end
        end
        if #sels == 0 then return end
        local current = vim.fn.getqflist({ items = 1 }).items or {}
        local function key(e)
          return table.concat({ e.bufnr or 0, e.lnum or 0, e.col or 0, e.text or '' }, '|')
        end
        local rm = {}
        for _, s in ipairs(sels) do rm[key(s.value)] = true end
        local kept = {}
        for _, it in ipairs(current) do if not rm[key(it)] then table.insert(kept, it) end end
        vim.fn.setqflist({}, ' ', { items = kept })
        require('telescope.actions').close(bufnr)
        M.qf_picker()
      end
      map('i', 'dd', delete_selected)
      map('n', 'dd', delete_selected)
      return true
    end,
  }):find()
end


-- Smart Files: Use git_files if in git, else find_files
function M.smart_files()
  local ok = pcall(require('telescope.builtin').git_files, { show_untracked = true })
  if not ok then require('telescope.builtin').find_files({ find_command = M.best_find_cmd() }) end
end

-- Turbo Find Files: Fast fd-based find
function M.turbo_find_files(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.expand('%:p:h')
  require('telescope.builtin').find_files({
    cwd = cwd,
    find_command = { (vim.fn.executable('fd') == 1 and 'fd' or 'fdfind'), '-H', '--ignore-vcs', '-d', '2', '--strip-cwd-prefix' },
    theme = 'ivy', previewer = false, prompt_title = false, sorting_strategy = 'descending', path_display = { 'truncate' },
  })
end

-- Turbo File Browser: Fast browser
function M.turbo_file_browser(opts)
  opts = opts or {}
  local cwd = opts.cwd or vim.fn.expand('%:p:h')
  local t = require('telescope'); pcall(t.load_extension, 'file_browser')
  t.extensions.file_browser.file_browser({
    cwd = cwd, theme = 'ivy', previewer = false, grouped = false, git_status = false,
    hidden = { file_browser = false, folder_browser = false }, respect_gitignore = true, prompt_title = false,
    layout_config = { height = 12 },
  })
end

return M
