{
  lib,
  pkgs,
  config,
  neg,
  ...
}:
let
  enable =
    (config.features.dev.enable or false)
    && (config.features.dev.ai.enable or false)
    && (config.features.dev.ai.pi.enable or false);

  # Globally installed pi via npm (prefix ~/.npm-global, not in PATH so nix wrapper takes priority).
  # Update with: pi update
  # Note: .npmrc sets prefix=$HOME/.npm-global so `pi update` works without PATH conflicts.
  piGlobal = "~/.npm-global/lib/node_modules/@earendil-works/pi-coding-agent/dist/cli.js";

  # Raw wrapper — no provider defaults, no secrets. Uses the global install for updatability.
  piLatest = pkgs.writeShellScriptBin "pi-latest" ''
    exec ${lib.getExe' pkgs.nodejs "node"} ${piGlobal} "$@"
  '';

  # Wrapper that injects secrets. Provider/model defaults come from settings.json
  # (defaultProvider: deepseek, defaultModel: deepseek/deepseek-v4-flash).
  # Flags deliberately omitted: they break `pi update`/`pi install` etc.
  # Takes precedence over the system-wide `pi` from pi.nix.
  piWrapper = pkgs.writeShellScriptBin "pi" ''
    set -a
    DEEPSEEK_API_KEY="$(${pkgs.coreutils}/bin/cat /run/secrets/deepseek-api 2>/dev/null || echo "''${DEEPSEEK_API_KEY:-}")"
    GITHUB_TOKEN="$(${pkgs.coreutils}/bin/cat /run/secrets/github-token 2>/dev/null || echo "''${GITHUB_TOKEN:-}")"
    set +a
    exec ${lib.getExe' pkgs.nodejs "node"} ${piGlobal} "$@"
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
      users.users.neg.packages = [ piWrapper piLatest ];
    }
    # Ensure .pi agent directory structure exists
    (neg.mkHomeFiles (
      {
        ".pi/agent/auth.json".text = "{}";
        # npm global prefix — writable, *not* in default PATH, so nix wrapper stays primary.
        # pi update uses this via its own path detection.
        ".npmrc".text = "prefix=\${HOME}/.npm-global\n";
      }
      // mkSubagentDirLinks "agents" subagentAgents
      // mkSubagentDirLinks "prompts" subagentPrompts
    ))
  ]
)
