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

  # npm-based pi 0.80.3 (updated from nixpkgs 0.75.4 for extension compatibility).
  # Installed via: npm install --prefix ~/.local @earendil-works/pi-coding-agent@0.80.3
  piLatest = pkgs.writeShellScriptBin "pi-latest" ''
    exec ${pkgs.nodejs}/bin/node /home/neg/.local/node_modules/@earendil-works/pi-coding-agent/dist/cli.js "$@"
  '';

  # Wrapper that defaults to DeepSeek provider and injects secrets.
  # Takes precedence over the system-wide `pi` from pi.nix.
  piWrapper = pkgs.writeShellScriptBin "pi" ''
    set -a
    DEEPSEEK_API_KEY="$(${pkgs.coreutils}/bin/cat /run/secrets/deepseek-api 2>/dev/null || echo "''${DEEPSEEK_API_KEY:-}")"
    GITHUB_TOKEN="$(${pkgs.coreutils}/bin/cat /run/secrets/github-token 2>/dev/null || echo "''${GITHUB_TOKEN:-}")"
    set +a
    exec ${pkgs.nodejs}/bin/node /home/neg/.local/node_modules/@earendil-works/pi-coding-agent/dist/cli.js --provider deepseek --model deepseek/deepseek-v4-flash "$@"
  '';

  # Subagent extension and prompts are now provided by npm:pi-subagents package.
  # Sample subagent definitions (scout, planner, reviewer, worker)
  subagentSrc = "${pkgs.pi-coding-agent}/lib/node_modules/pi-monorepo/examples/extensions/subagent";
  subagentAgents = [ "scout.md" "planner.md" "reviewer.md" "worker.md" ];
  subagentPrompts = [ "implement.md" "scout-and-plan.md" "implement-and-review.md" ];

  mkSubagentDirLinks = dir: files: builtins.listToAttrs (builtins.map (f: {
    name = ".pi/agent/${dir}/${f}";
    value.source = "${subagentSrc}/${dir}/${f}";
  }) files);
in
lib.mkIf enable (
  lib.mkMerge [
    # User-local pi wrapper (deepseek by default + secrets)
    {
      users.users.neg.packages = [ piWrapper ];
    }
    # Ensure .pi agent directory structure exists
    (n.mkHomeFiles (
      {
        ".pi/agent/auth.json".text = "{}";
      }
      # Subagent agents and prompts (extensions now from npm:pi-subagents)
      // mkSubagentDirLinks "agents" subagentAgents
      // mkSubagentDirLinks "prompts" subagentPrompts
    ))
  ]
)
