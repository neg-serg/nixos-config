local au = vim.api.nvim_create_autocmd
local gr = vim.api.nvim_create_augroup

local main = gr("main", {clear=true})
local utils = gr("utils", {clear=true})
local hi_yank = gr("hi_yank", {clear=true})

-- Auto set window-local cwd to project root for reliable gf/path resolution.
-- Root detection delegates to utils/nav.lua (cached, unified marker set).
do
  local nav = require('utils.nav')
  local pr = gr('AutoProjectRoot', { clear = true })
  au({ 'BufEnter', 'BufNewFile' }, {
    group = pr,
    callback = function(args)
      if vim.bo[args.buf].buftype ~= '' then return end
      local name = vim.api.nvim_buf_get_name(args.buf)
      if not name or name == '' then return end
      local filedir = vim.fn.fnamemodify(name, ':p:h')
      local root = nav.project_root(filedir) or filedir
      if root and vim.fn.getcwd(0) ~= root then pcall(vim.cmd.lcd, root) end
    end,
    desc = 'Auto-set local cwd to project root',
  })
end

local function restore_cursor()
    au('FileType', { buffer=0, once=true,
        callback = function()
            if vim.fn.expand('%') == '' or vim.bo.buftype ~= '' then return end
            local ft = vim.bo.filetype
            if ft == 'gitcommit' or ft == 'gitrebase' or ft == 'commit' or ft == 'rebase' then return end
            local mark = vim.fn.line([['"]])
            if mark > 0 and mark <= vim.fn.line('$') then
                vim.cmd.normal{[[g`"zv']], bang=true}
            end
        end,
    })
end

au({'FocusGained','FileChangedShell'}, {callback=function() vim.cmd.checktime() end, group=main})
-- Close transient windows with q
au({'Filetype'}, {
    pattern={'help', 'startuptime', 'qf', 'lspinfo'},
    callback=function(args)
        vim.keymap.set('n', 'q', '<Cmd>close<CR>', {buffer=args.buf, silent=true})
    end,
    group=main})
au('TermOpen', {pattern='term://*', callback=function()
    vim.cmd.startinsert()
    vim.wo.number = false
    vim.wo.stl = ' terminal %='
end, group=main})
au('BufLeave', {pattern='term://*', callback=function() vim.cmd.stopinsert() end, group=main})
au({"BufReadPost"}, {callback=restore_cursor, group=main, desc="auto line return"})
-- Clear search register at startup so hlsearch doesn't restore stale matches from shada.
au('VimEnter', {callback=function() vim.fn.setreg('/', '') end, once=true, group=main})
au('BufWritePost', {pattern='fonts.conf', callback=function()
    vim.system({'fc-cache'}, { detach = true })
end, group=main})
au({'TextYankPost'}, {
    callback=function() vim.hl.on_yank{timeout=60, higroup="Search"} end,
    group=hi_yank})
au({'DirChanged'}, {pattern={'window','tab','tabpage','global'}, callback=function()
    vim.system({'zoxide', 'add', vim.fn.getcwd()}, { detach = true })
    end,group=main})
au('BufWritePost', {pattern='*',
    callback=function(args)
        if vim.bo[args.buf].buftype ~= '' then return end
        if vim.fn.getline(1):find('^#!.*/bin/') then
            vim.system({'chmod', 'a+x', vim.fn.expand('<afile>')}, { detach = true })
        end
    end, group=utils})
au({'BufNewFile','BufWritePre'}, {pattern='*',
    callback=function(args)
        local dir = vim.fn.fnamemodify(args.file, ':p:h')
        if not dir:find('://') then vim.fn.mkdir(dir, 'p') end
    end, group=utils})

vim.g.markdown_fenced_languages={'shell=bash'}
vim.filetype.add({
  extension = { rasi = 'scss', ignore = 'gitignore', ojs = 'javascript', astro = 'astro', mdx = 'mdx', tidal = 'tidal' },
  filename = { ['flake.lock'] = 'json' },
})

-- Tune 'path' and 'suffixesadd' per filetype to reduce gf collisions
do
  local gfaug = gr('GfGlobalTuning', { clear = true })
  au({ 'BufEnter', 'BufNewFile' }, {
    group = gfaug,
    callback = function(args)
      -- Buffer-local guard: suffixesadd only needs to be set once per buffer.
      -- (suffixesadd is window-local but the extension is constant per file.)
      if vim.b[args.buf]._gf_suffixes_set then return end
      local name = vim.api.nvim_buf_get_name(args.buf)
      if not name or name == '' then return end
      local ext = vim.fn.fnamemodify(name, ':e')
      if not ext or ext == '' then return end
      local dotext = '.' .. ext
      local cur = vim.opt_local.suffixesadd:get()
      for _, s in ipairs(cur) do
        if s == dotext then
          vim.b[args.buf]._gf_suffixes_set = true
          return
        end
      end
      pcall(function() vim.opt_local.suffixesadd:prepend({ dotext }) end)
      vim.b[args.buf]._gf_suffixes_set = true
    end,
    desc = 'Prioritize current extension in suffixesadd',
  })

  local ft_preferred_dirs = {
    python = { 'src', 'tests' },
    lua = { 'lua', 'plugin' },
    javascript = { 'src', 'lib' },
    typescript = { 'src', 'lib' },
    javascriptreact = { 'src', 'lib', 'components' },
    typescriptreact = { 'src', 'lib', 'components' },
    rust = { 'src' },
    c = { 'src', 'include' },
    cpp = { 'src', 'include' },
    objc = { 'src', 'include' },
    objcpp = { 'src', 'include' },
    nix = { 'nix' },
    sh = { 'scripts', 'shell' },
    bash = { 'scripts', 'shell' },
    zsh = { 'scripts', 'shell' },
  }
  local function prepend_unique_path_dirs(dirs)
    if not dirs or vim.tbl_isempty(dirs) then return end
    local items = {}
    for _, d in ipairs(dirs) do table.insert(items, d); table.insert(items, d .. '/**') end
    local present = {}
    for _, p in ipairs(vim.opt_local.path:get()) do present[p] = true end
    for i = #items, 1, -1 do
      local it = items[i]
      if not present[it] then vim.opt_local.path:prepend(it); present[it] = true end
    end
  end
  au('FileType', {
    group = gfaug,
    callback = function(args)
      local ft = args.match or vim.bo[args.buf].filetype
      prepend_unique_path_dirs(ft_preferred_dirs[ft])
    end,
  })
end
