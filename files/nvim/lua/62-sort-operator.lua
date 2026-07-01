-- Sort operator: use <leader>s{motion} to sort lines in range
local function sort_opfunc()
  vim.cmd("'[,']sort")
end

vim.keymap.set('n', '<leader>s', function()
  _G._neg_sort_opfunc = sort_opfunc
  vim.o.operatorfunc = 'v:lua._neg_sort_opfunc'
  return 'g@'
end, { expr = true, desc = 'Sort lines (operator)' })
