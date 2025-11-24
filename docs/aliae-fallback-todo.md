# Aliae Zsh fallback (TODO)

For now, Zsh loads a local alias fallback in `home/files/shell/zsh/06-aliae-fallback.zsh` that mirrors the alias set from `modules/cli/aliae.nix`. This keeps core aliases available even when the `aliae` binary or config is broken or missing.

TODO:

- Remove `home/files/shell/zsh/06-aliae-fallback.zsh` and its wiring in `home/files/shell/zsh/.zshrc` once `aliae init zsh` is reliable again and the `aliae/config.yaml` flow works end-to-end.

