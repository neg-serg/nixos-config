-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ nvim-orgmode/orgmode                                                         │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'nvim-orgmode/orgmode',
    ft = 'org',
    cmd = { 'OrgAgenda', 'OrgCapture' },
    config=function()
        require'orgmode'.setup({
            org_agenda_files='~/orgfiles/**/*',
            org_default_notes_file='~/orgfiles/refile.org',
        })
    end,
}
