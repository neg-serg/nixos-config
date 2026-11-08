{ pkgs, ... }: {
  # light text processing and previewing tools
  nativeBuildInputs = [
    pkgs.recoll # metadata-based full-text desktop search tool
  ];
}
