-- ┌───────────────────────────────────────────────────────────────────────────────────┐
-- │ █▓▒░ mason.nvim — portable LSP/formatter/linter installer.                       │
-- │ LSP servers are provided via nixpkgs (environment.systemPackages), not Mason —   │
-- │ Mason binaries break on NixOS (no /lib64/ld-linux, no /usr/bin/env).             │
-- │ Mason is kept only for the visual package browser (`:Mason`).                    │
-- └───────────────────────────────────────────────────────────────────────────────────┘
return {
  'mason-org/mason.nvim',
  cmd = { 'Mason', 'MasonInstall', 'MasonUpdate', 'MasonLog' },
  opts = {},
}
