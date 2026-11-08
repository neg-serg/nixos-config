{
  pkgs,
  lib,
  config,
  neg,
  ...
}:
let
  inherit (config.users.users.neg) home;
  onDemand = config.lib.neg.onDemand pkgs;
in
lib.mkMerge [
  {
    environment.systemPackages = [
      pkgs.aliae # Shell alias manager
      # TODO(neg): remove fastfetch for good together with the blizzard stack
      # (modules/user/nix-maid/cli/fastfetch.nix, files/fastfetch/). Until then
      # it is on demand: the launcher builds packages.x86_64-linux.fastfetch on
      # first call and GC-roots it under ~/.local/state/nix-apps.
      (onDemand {
        name = "fastfetch";
        attr = "fastfetch";
      }) # System info tool (neofetch successor); zfsSupport in the flake attr keeps the zpool module
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

    ".config/amfora".source = config.lib.neg.live "files/config/amfora";

    ".config/tealdeer/config.toml".text = config.lib.neg.readFile "files/tealdeer/config.toml";
  })
]
