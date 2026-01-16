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

      # ZCLI (custom script)
      (import ../../../../files/scripts/zcli.nix {
        inherit pkgs;
        profile = "telfir"; # Host profile for script configuration
        repoRoot = "/etc/nixos";
        flakePath = "/etc/nixos/flake.nix";
        backupFiles = [ ];
      })
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
    ".config/tealdeer/config.toml".text = ''
      [style.description]
      underline = false
      bold = false
      italic = true

      [style.command_name]
      foreground = "cyan"
      underline = false
      bold = false
      italic = false

      [style.example_text]
      foreground = "green"
      underline = false
      bold = false
      italic = false

      [style.example_code]
      foreground = "yellow"
      underline = false
      bold = false
      italic = true

      [style.example_variable]
      foreground = "blue"
      underline = false
      bold = true
      italic = false

      [display]
      compact = false
      use_pager = false

      [updates]
      auto_update = true
      auto_update_interval_hours = 720

      [directories]
    '';
  })
]
