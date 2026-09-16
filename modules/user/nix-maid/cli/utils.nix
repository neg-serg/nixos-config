{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
in
lib.mkMerge [
  {
    environment.systemPackages = [
      pkgs.aliae # Shell alias manager
      (pkgs.fastfetch.override { zfsSupport = true; }) # System info tool (neofetch successor; zfsSupport enables zpool module)
      pkgs.tealdeer # Fast tldr client
      pkgs.nxv # Find any version of any Nix package instantly
    ];

    environment.variables = {
      HTTPIE_CONFIG_DIR = "${home}/.config/httpie";
      PARALLEL_HOME = "${home}/.config/parallel";
    };
  }

  (neg.mkHomeFiles {
    ".config/fastfetch/config.jsonc".text = config.lib.neg.readFile "files/fastfetch/config.jsonc";

    ".config/fastfetch/skull".text = builtins.readFile (config.lib.neg.path "files/fastfetch/skull");

    ".config/amfora".source = config.lib.neg.path "files/config/amfora";

    ".config/tealdeer/config.toml".text = config.lib.neg.readFile "files/tealdeer/config.toml";
  })
]
