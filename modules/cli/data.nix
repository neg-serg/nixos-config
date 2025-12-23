{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.jq # ubiquitous JSON processor for scripts
    pkgs.miller # awk/cut/join alternative for CSV/TSV/JSON
    pkgs.taplo # TOML toolkit (fmt/lsp/lint)
    pkgs.xidel # extract webpage segments
  ];
}
