-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ pianocomposer321/officer.nvim                                                │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'pianocomposer321/officer.nvim',
    dependencies = 'stevearc/overseer.nvim',
    config = function()
        require('officer').setup{}
    end
}
