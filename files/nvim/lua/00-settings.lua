local o=vim.opt
local env_=vim.env
local home_=env_.HOME
local config_home_=env_.XDG_CONFIG_HOME or (home_..'/.config')
local data_home_=env_.XDG_DATA_HOME or (home_..'/.local/share')
local appname=env_.NVIM_APPNAME or 'nvim'
local config_dir=config_home_..'/'..appname
local data_dir=data_home_..'/'..appname
o.sessionoptions='blank,buffers,curdir,folds,help,tabpages,winsize'
local disabled_built_ins={
    '2html_plugin',
    'bugreport',
    'compiler',
    'getscript',
    'getscriptPlugin',
    'gzip',
    'logipat',
    'matchit',
    'matchparen',

    'optwin',
    'rplugin',
    'rrhelper',
    'spellfile_plugin',
    'synmenu',
    'syntax',
    'tar',
    'tarPlugin',
    'tutor',
    'vimball',
    'vimballPlugin',
    'zip',
    'zipPlugin',
}
for _, plugin in pairs(disabled_built_ins) do
    vim.g['loaded_'..plugin]=1
end
vim.g.loaded_node_provider=0
vim.g.loaded_perl_provider=0
vim.g.loaded_ruby_provider=0

-- Defer executable() checks to VeryLazy (synchronous PATH scans are slow at startup)
vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy', once = true,
  callback = function()
    if vim.fn.executable('ugrep') == 1 then
      vim.o.grepprg = 'ugrep -RInk -j -u --tabs=1 --ignore-files'
      vim.o.grepformat = '%f:%l:%c:%m,%f+%l+%c+%m,%-G%f\\|%l\\|%c\\|%m'
    end
    if vim.fn.executable('nvr') == 1 then
      vim.env.GIT_EDITOR = "nvr -cc split +'setl bh=delete' --remote-wait"
      vim.env.EDITOR = 'nvr -l --remote'
      vim.env.VISUAL = 'nvr -l --remote'
    end
  end,
})
o.path='.,..,'..config_dir..','..
    config_dir..'/lua,'..
    config_dir..'/after,'..
    data_dir..'/site/,/usr/include'
-- Allow recursive file lookup for gf/:find
vim.opt.path:append('**')
o.fillchars={foldopen="", foldclose="",
    fold=" ", foldsep=" ",
    diff="╱", eob=" "}
o.formatprg='par -140'                       -- Better format
o.report=0                                   -- No report on substitution
o.fileformats='unix,dos,mac'                 -- File format fallback
o.conceallevel=1                             -- Enable conceal without hide
o.concealcursor='n'                          -- Conceal cursor
o.keymap='russian-jcukenwin'                 -- Add ru keymap
o.backup=true                                -- Backuping is good
o.cedit='<C-y>'                              -- Enter Command-line Mode from command-mode
o.clipboard='unnamedplus'                    -- Always clipboard all operations
o.cindent=true                               -- Smart indenting for c-like code
o.cinoptions='b1,g0,N-s,t0,(0,W4'            -- See :h cinoptions-values
o.copyindent=true                            -- Copy the previous indentation on autoindenting
o.diffopt='internal,filler,closeoff,algorithm:patience,indent-heuristic' -- Use the indent heuristic for the internal diff library.
o.eadirection='hor'                          -- Ver/hor/both - where does equalalways apply
o.expandtab=true                             -- Tabs are spaces=not tabs
o.fileencodings='utf-8,default'              -- Less file encodings
o.gdefault=true                              -- This makes search/replace global by default
o.ignorecase=true                            -- Case insensitive search
o.iminsert=0                                 -- Use Latin input in Insert by default
o.imsearch=0                                 -- Search with latin1 characters first
o.isfname='#,$,%,+,,,-,.,/,48-57,=,@,_,~,@-@'  -- Scan in filenames in such brackets
o.matchtime=0                                -- Default time to hi brackets too long for me
o.matchpairs='(:),{:},[:],<:>'                 -- More matchpairs
o.foldenable=false                           -- Disable folds as
o.relativenumber=false                        -- Relative line numbers
o.number=false                                -- No line numbers at all
o.numberwidth=3                              -- Shorter number width
o.signcolumn='yes:3'                         -- 3 slots for diagnostic/git/dap signs
o.pumblend=15                                -- setup pmenu transparency
o.pumheight=10                               -- Do not make pmenu too wide
o.scrolljump=0                               -- Lines to scroll when cursor leaves screen
o.scrollback=10000                             -- Terminal scrollback lines
o.shiftwidth=4                               -- Spaces for autoindents
o.wildignorecase=true                        -- Ignore case for wildmenu
o.wildignore='*.7z,*.aux,*.avi,*.bak,*.bib,*.class,*.cls,*.cmi,'..
    '*.cmo,*.doc,*.docx,*.dvi,*.flac,*.flv,*.gif,*.ico,'..
    '*.jpeg,*.jpg,*.log,*.min*.js,*.mov,*.mp3,*.mp4,*.mpg,'..
    '*.nav,*.o,*.ods,*.odt,*.ogg,*.opus,*.out,*.pdf,*.pem,'..
    '*.png,*.rar,*.sty,*.svg,*.swp,*.swp*.,*.tar,*.tgz,'..
    '*.toc,*.wav,*.webm,*.xcf,*.xls,*.xlsx,*.zip'
o.shortmess='OcsliFtfnToAIqx'                  -- Shorting messages for all
o.more=false                                 -- Do not ask to press enter
o.showmode=false                             -- Do not show the mode ("-- INSERT --" at the bottom)
o.showcmd=false                              -- Do not show command output
o.showtabline=0                              -- Do not show tab line
o.smartcase=true                             -- Case sensitive when uc present
o.softtabstop=4                              -- Let backspace delete indent
o.switchbuf='useopen,usetab'                 -- useopen may be useful for re-using QuickFix window.
o.tabstop=4                                  -- An indentation every four columns
o.timeoutlen=400                             -- 400 ms wait to sequence complete
o.ttimeoutlen=20                             -- Very fast and also you shouldnt make combination too fast
o.updatetime=100                             -- Faster diagnostics
o.redrawtime=1500                            -- Shorter redrawtime
o.virtualedit='onemore,block'                -- Allow for cursor beyond last character
o.whichwrap='b,s,h,l,<,>,[,]'                -- Backspace and cursor keys wrap too
o.wildoptions={'pum'}                        -- Wild options
o.winblend=15                                -- Pseudo-transparency for floating windows
o.winminheight=0                             -- Windows can be 0 line high
o.winminwidth=0                              -- Windows can be 0 line width
o.wrap=false                                 -- Do not wrap lines by default
o.mouse='a'                                  -- Add mouse support
o.mousescroll={'ver:2','hor:1'}              -- More conservative mouse scroll
o.backupdir=home_..'/trash/'               -- Setup backupdir
o.directory=home_..'/trash/'               -- Directory for swap files
o.undodir=data_dir..'/undo'                 -- Setup undo dir
o.undofile=true                              -- Enable undofile
o.swapfile=false                             -- Do not use swapfiles

-- Disable undofile for sensitive files to prevent leaking secrets via undo history
vim.api.nvim_create_autocmd('BufReadPre', {
  pattern = { '*.gpg', '*.asc', '*.env', '*/.env.*', '*/gopass-*', '/dev/shm/*', 'COMMIT_EDITMSG' },
  callback = function()
    vim.bo.undofile = false
    vim.bo.swapfile = false
  end,
})
o.shada=[['1000,<50,s10,h]]                     -- Ultra fast shada settings
-- Defer ShaDa reading to after first screen render
local orig_shadafile = vim.o.shadafile
vim.o.shadafile = 'NONE'
vim.api.nvim_create_autocmd('UIEnter', {
  once = true,
  callback = function()
    vim.o.shadafile = orig_shadafile
    pcall(vim.cmd, 'rshada')
  end,
})
o.cdhome=true                                -- :cd without argument goes to the home directory
o.completeopt='menu,menuone,noselect'        -- Completion options
o.formatoptions='n1jcroql'                    -- Format settings
o.cpoptions='_$ABFWcdesa'                    -- Vim-exclusive stuff
o.ruler=false                                -- No ruler
o.cmdheight=0                                -- Fancy cmdheight for neovim
o.laststatus=3                               -- One statusline for all

-- Russian langmap (extracted from langmapper for fast startup)
do
  local function escape(str)
    local escape_chars = [[;,."|\]]
    return vim.fn.escape(str, escape_chars)
  end
  local en = [[`qwertyuiop[]asdfghjkl;'zxcvbnm]]
  local ru = [[ёйцукенгшщзхъфывапролджэячсмить]]
  local en_shift = [[~QWERTYUIOP{}ASDFGHJKL:"ZXCVBNM<>]]
  local ru_shift = [[ËЙЦУКЕНГШЩЗХЪФЫВАПРОЛДЖЭЯЧСМИТЬБЮ]]
  o.langmap = vim.fn.join({
    escape(ru_shift) .. ';' .. escape(en_shift),
    escape(ru) .. ';' .. escape(en),
  }, ',')
end
