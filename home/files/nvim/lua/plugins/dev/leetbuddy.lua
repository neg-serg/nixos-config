-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ Dhanus3133/LeetBuddy.nvim                                                    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'Dhanus3133/LeetBuddy.nvim', -- leetcode helper

    dependencies={'nvim-lua/plenary.nvim', 'nvim-telescope/telescope.nvim'},
    config=function() require'leetbuddy'.setup({}) end,
    keys={
        {'<leader>Lq', '<cmd>LBQuestions<cr>', desc='LeetBuddy: List Questions'},
        {'<leader>Ll', '<cmd>LBQuestion<cr>', desc='LeetBuddy: View Question'},
        {'<leader>Lr', '<cmd>LBReset<cr>', desc='LeetBuddy: Reset Code'},
        {'<leader>Lt', '<cmd>LBTest<cr>', desc='LeetBuddy: Run Code'},
        {'<leader>Ls', '<cmd>LBSubmit<cr>', desc='LeetBuddy: Submit Code'}}}
