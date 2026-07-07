{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  n = neg;
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.pi.enable or false);

  # Wrapper that defaults to DeepSeek provider and injects secrets.
  # Takes precedence over the system-wide `pi` from pi.nix.
  piWrapper = pkgs.writeShellScriptBin "pi" ''
    set -a
    DEEPSEEK_API_KEY="$(${pkgs.coreutils}/bin/cat /run/secrets/deepseek-api 2>/dev/null || echo "''${DEEPSEEK_API_KEY:-}")"
    GITHUB_TOKEN="$(${pkgs.coreutils}/bin/cat /run/secrets/github-token 2>/dev/null || echo "''${GITHUB_TOKEN:-}")"
    set +a
    exec ${pkgs.pi-coding-agent}/bin/pi --provider deepseek --model deepseek/deepseek-v4-flash "$@"
  '';
in
lib.mkIf enable (
  lib.mkMerge [
    # User-local pi wrapper (deepseek by default + secrets)
    {
      users.users.neg.packages = [ piWrapper ];
    }
    # Ensure .pi agent directory structure exists
    (n.mkHomeFiles {
      ".pi/agent/auth.json".text = "{}";
    })
  ]
)
