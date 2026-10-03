-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ lervag/vimtex                                                                │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'lervag/vimtex',
  ft = { 'tex', 'latex', 'plaintex', 'cls', 'tikz', 'bib' },
  init = function()
    -- TeX is not installed system-wide: the toolchain lives in the repo's
    -- `latex` devshell (texlive scheme-full + rubber + sioyek). Start nvim from
    -- `nix develop .#latex` (or via direnv in that shell) and `\ll` can build.
    -- rubber is the wrapper that devshell ships; without it VimTeX keeps its
    -- default latexmk backend.
    if vim.fn.executable('rubber') == 1 then
      vim.g.vimtex_compiler_method = 'generic'
      vim.g.vimtex_compiler_generic = {
        command = 'rubber --pdf --force @tex', -- @tex = main file of the project
      }
    end
  end,
}
