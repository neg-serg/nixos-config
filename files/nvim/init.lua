if vim.fn.has("nvim-0.11") ~= 1 then
    vim.notify("This config requires Neovim 0.11+", vim.log.levels.ERROR)
end
vim.loader.enable()
vim.g.mapleader = ','
vim.g.maplocalleader = ','
require'00-settings'
require'01-plugins'

-- Defer all non-critical modules to after first screen render
vim.api.nvim_create_autocmd('User', {
  pattern = 'VeryLazy', once = true,
  callback = function()
    require'02-bindings'
    require'04-aucmds'
    require'08-cmds'
    require'14-abbr'
    require'62-sort-operator'
  end,
})

