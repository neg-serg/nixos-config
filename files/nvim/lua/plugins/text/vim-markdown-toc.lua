-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mzlogin/vim-markdown-toc                                                     │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {'mzlogin/vim-markdown-toc', ft='markdown', -- table of contents generator
        cmd={'GenTocGFM','GenTocRedcarpet','GenTocGitLab','GenTocMarked','UpdateToc','RemoveToc'}}
