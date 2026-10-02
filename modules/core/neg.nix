{
  lib,
  neg,
  repoRoot,
  config,
  ...
}:
let
  # Primary (login) user name. `users.main` is declared by
  # modules/system/users.nix; keep the "neg" fallback for hosts that omit it.
  mainUser = config.users.main.name or "neg";

  # Effective passwd entry for the primary user (may be absent in trimmed
  # evals; each field below falls back individually).
  mainUserEntry = lib.attrByPath [ "users" "users" mainUser ] { } config;

  # Repo-root resolver (lib/neg-helpers.nix `rooted`): path / pathExists /
  # readFile / tree / find. Spread into lib.neg below, so
  # `config.lib.neg.path "files/x"` and `config.lib.neg.repo.find …` are the
  # same thing, and every call site outside a module context can build the very
  # same object from its own repoRoot.
  repo = neg.rooted repoRoot;
in
{
  options.neg = {
    repoRoot = lib.mkOption {
      type = lib.types.path;
      # Path literal for the repo root, injected via specialArgs from
      # flake/nixos.nix (real path, not a string — string paths are not
      # tracked in derivation closures and can be garbage-collected).
      default = repoRoot;
      description = "Path to the root of the configuration repository.";
    };

  };

  config = {
    _module.args.mkBool = desc: default: (lib.mkEnableOption desc) // { inherit default; };

    # Expose helpers under config.lib.neg: the pure neg-helpers from
    # specialArgs (mkHomeFiles, importDir, ...) extended with helpers that
    # close over config.
    lib.neg =
      neg
      // repo
      // rec {
        # Primary user identity — single source for the preamble
        # (`user = config.users.main.name or "neg"` plus the attrByPath lookups
        # for home/group) that modules used to repeat.
        inherit mainUser;
        homeDir = mainUserEntry.home or "/home/${mainUser}";
        mainGroup = mainUserEntry.group or mainUser;

        # enabled "gui" → features.gui.enable, or false when unset. Sites that
        # previously wrote `or true` (default-on) keep the explicit form.
        #
        # Keep this a plain predicate used inside a value, e.g.
        # `config = lib.mkIf (config.lib.neg.enabled "x") { … }`. Do NOT add a
        # `gate = path: body: lib.mkIf (config.lib.neg.enabled path) body` and
        # apply it at module top level: the module's shape would then depend on
        # `config`, which is evaluated before the config fixpoint exists →
        # infinite recursion (tried in the gate-adoption refactor, reverted).
        enabled =
          path:
          (lib.attrByPath (lib.splitString "." path) { enable = false; } config.features).enable or false;

        # Wi-Fi stack: the host profile opt-in (profiles.network.wifi.enable) or
        # the net.wifi feature. Four modules used to repeat this predicate.
        wifiEnabled = (config.profiles.network.wifi.enable or false) || enabled "net.wifi";

        # Quickshell panel: full GUI + Qt + quickshell flags, off in dev-speed
        # mode. Three modules used to repeat this conjunction.
        quickshellEnabled =
          enabled "gui" && enabled "gui.qt" && enabled "gui.quickshell" && !(enabled "devSpeed");

        # Repo-root resolver (`path`, `pathExists`, `readFile`, `tree`, `find`) is
        # spread in above from the top-level `repo` binding: repoRoot is a real
        # path, so `repo.path "files/x"` carries Nix path context — used in a
        # derivation or a home file the target is copied into the store and tracked
        # as a closure dependency, exactly like the old relative `./../../`
        # references. It must never become a plain string: strings are not added to
        # derivation closures and their files can be garbage-collected away.
        # NB: the leading slash stays inside the same string operand — `path + "/"`
        # normalizes the trailing slash away and the join breaks.

        # Data index of files/ — the by-name alternative to string literals:
        # `config.lib.neg.files.mpv."hdr-auto-switch"` instead of
        # `path "files/mpv/hdr-auto-switch.lua"`, so a typo lists the real keys.
        # Lazily built: nothing walks files/ unless something reads this.
        files = repo.tree {
          dir = "files";
          extensions = "any";
        };

        # Per-user systemd unit helpers (lib/systemd-user.nix). The module closes
        # over `lib` only, so callers no longer import it themselves.
        systemdUser = neg.systemdUser lib;

        # Shared llama-server systemd unit skeleton (lib/llama-server.nix).
        llamaServer = neg.llamaServer lib;
      };
  };
}
