{
  pkgs,
  lib,
  config,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  fastfetchSrc = ../../../../files/fastfetch;
in
lib.mkMerge [
  {
    environment.systemPackages = [
      pkgs.aliae # Cross-shell configuration manager
      pkgs.fastfetch # Like neofetch, but much faster (C)
      pkgs.tealdeer # A fast tldr client in Rust
      pkgs.nodejs # For npx and npm
    ];

    # --- Environment Variables ---
    environment.variables = {
      HTTPIE_CONFIG_DIR = "${config.users.users.neg.home}/.config/httpie";
      PARALLEL_HOME = "${config.users.users.neg.home}/.config/parallel";
    };
  }

  (n.mkHomeFiles {
    # Fastfetch Configs (Source from repo)
    ".config/fastfetch/config.jsonc".source = n.linkImpure (fastfetchSrc + /config.jsonc);
    ".config/fastfetch/skull".source = n.linkImpure (fastfetchSrc + /skull); # Custom logo

    # Amfora Config
    ".config/amfora".source = ../../../../files/config/amfora;

    # Tealdeer Config
    ".config/tealdeer/config.toml".source = n.linkImpure ../../../../files/tealdeer/config.toml;
  })
]
