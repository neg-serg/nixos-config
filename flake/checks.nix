# Checks for parallel evaluation via nix-eval-jobs.
#
# Each check exercises an independent subset of the NixOS module tree.
# nix-eval-jobs dispatches every flake output attribute as a separate job,
# so adding checks here creates additional parallel eval units that run
# alongside nixosConfigurations, devShells, etc.
#
# Domain filter refactoring (Jul 2026):
#   modules/default.nix now accepts domainFilter via specialArgs, letting
#   test configurations restrict which module domains are imported (smaller
#   eval trees). These module checks validate that the filter mechanism works.
# ---------------------------------------------------------------------------
{
  nixpkgs,
  self,
  inputs,
  mkTestHost,
  ...
}:
pkgs:
let
  inherit (nixpkgs) lib;

  # Real specialArgs that the module tree needs for evalModules.
  # The dom-* checks evaluate the FULL module tree via modules/default.nix,
  # so they need the real inputs (modules reference inputs.steam-config-nix,
  # inputs.hyprscratch, ...) — only the structural extras are stubbed.
  mkStubArgs = domainFilter: {
    inherit domainFilter;
    inputs = inputs // {
      inherit self;
    };
    locale = "C";
    timeZone = "UTC";
    filteredSource = self;
    iosevkaNeg = { };
    # Repo root as a real path literal — same as flake/nixos.nix specialArgs.
    repoRoot = ../.;
    # Real helpers (lib/neg-helpers.nix) — their home/user config outputs are
    # inert here because evalModules runs with _module.check = false.
    neg = import ../lib/neg-helpers.nix;
  };

  mkModuleCheck =
    name: extraModules: domainFilter:
    let
      result = lib.evalModules {
        specialArgs = mkStubArgs domainFilter;
        modules = [
          { _module.check = false; }
          ../modules/features
        ]
        ++ extraModules;
      };
    in
    pkgs.runCommand "check-${name}" { } ''
      echo "check: ${name} OK (${toString (builtins.length (builtins.attrNames result.options))} options)"
      touch $out
    '';

in
{
  # ── Module-level checks ──────────────────────────────────────────
  # Each validates a domain or domain set independently.

  "mod-features" = mkModuleCheck "features" [ ] (_: true);
  "mod-profiles" = mkModuleCheck "profiles" [ ../modules/profiles/default.nix ] (_: true);
  "mod-core" = mkModuleCheck "core" [ ../modules/core/default.nix ] (_: true);

  # ── Domain filter checks ─────────────────────────────────────────
  # Validate that modules/default.nix (the actual filter consumer) works
  # with both the all-domains and a restrictive filter (mirrors the
  # odinDomains path in flake/nixos.nix).

  "dom-all" = mkModuleCheck "dom-all" [ ../modules/default.nix ] (_: true);

  "dom-restrictive" = mkModuleCheck "dom-restrictive" [ ../modules/default.nix ] (
    name: name != "user" && name != "games"
  );

  # ── Unit checks (pure nix, eval-only) ──────────────────────────────
  # lib/ru-keys.nix is the single source of truth for ЙЦУКЕН hotkey
  # duplicates; these assertions pin the table and every generator.
  "ru-keys" =
    let
      t = import ../lib/ru-keys-tests.nix { lib = nixpkgs.lib; };
    in
    if t.failures == [ ] then
      pkgs.runCommand "check-ru-keys" { } ''
        echo "check: ru-keys OK (${toString (builtins.length t.checks)} assertions)"
        touch $out
      ''
    else
      builtins.throw "ru-keys check failures: ${t.report}";

  # ── fzf opts guards ────────────────────────────────────────────────
  # fzf parses FZF_*_OPTS values as its own CLI options; a standalone '#'
  # token silently truncates them (regression: commit 5cd4942a dropped all
  # colors/binds). fzf-opts-guard pins the predicate, fzf-opts parses the
  # real odin values with fzf itself.

  "fzf-opts-guard" =
    let
      t = import ../lib/fzf-opts-tests.nix;
    in
    if t.failures == [ ] then
      pkgs.runCommand "check-fzf-opts-guard" { } ''
        echo "check: fzf-opts-guard OK (${toString (builtins.length t.checks)} assertions)"
        touch $out
      ''
    else
      builtins.throw "fzf-opts-guard check failures: ${t.report}";

  "fzf-opts" =
    let
      vars = self.nixosConfigurations.odin.config.environment.variables;
      fzfOpts = [
        {
          name = "FZF_DEFAULT_OPTS";
          value = vars.FZF_DEFAULT_OPTS;
        }
        {
          name = "FZF_CTRL_R_OPTS";
          value = vars.FZF_CTRL_R_OPTS;
        }
        {
          name = "FZF_CTRL_T_OPTS";
          value = vars.FZF_CTRL_T_OPTS;
        }
      ];
    in
    pkgs.runCommand "check-fzf-opts"
      {
        nativeBuildInputs = [ pkgs.fzf ];
      }
      (
        lib.concatMapStrings (o: ''
          echo "check: fzf parses ${o.name}"
          opts="$(cat ${pkgs.writeText "fzf-${o.name}" o.value})"
          # 1) every option must be valid — an unknown/invalid option makes fzf exit != 0
          printf 'probe\n' | FZF_DEFAULT_OPTS="$opts" fzf --filter=probe >/dev/null
          # 2) a standalone '#' comment would silently eat the appended sentinel
          #    (exit 0) — a clean string must reject it (exit != 0)
          if printf 'probe\n' | FZF_DEFAULT_OPTS="$opts --no-such-fzf-sentinel-xyz" fzf --filter=probe >/dev/null 2>&1; then
            echo "FAIL: ${o.name} contains a standalone '#' comment — fzf silently dropped the rest of the options" >&2
            exit 1
          fi
          echo "check: fzf opts ${o.name} OK"
        '') fzfOpts
        + ''
          touch $out
        ''
      );

  # ── dsh-worktree guard ─────────────────────────────────────────────
  # packages/local-bin/bin/dsh-worktree creates real git worktrees outside the
  # repository so parallel dsh sessions never fight over the working copy. The
  # guard pins the contract: trees stay out of the main checkout's `git status`,
  # each carries its own branch, and a dirty tree is not removed without
  # --force. It runs against a throwaway repository in $TMPDIR.

  "dsh-worktree-guard" =
    pkgs.runCommand "check-dsh-worktree"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.git
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        bash ${../scripts/dev/check-dsh-worktree.sh} ${../packages/local-bin/bin/dsh-worktree}
        touch $out
      '';

  # ── dsh-statusline guard ───────────────────────────────────────────
  # packages/local-bin/bin/dsh-statusline is the content half of the status
  # line: session JSON on stdin, one line on stdout. The guard pins the protocol
  # subset (branch, dirty counts, context from ratio or tokens/max, turn), the
  # worktree naming, DSH_STATUSLINE_PARTS, and that a missing field degrades
  # instead of printing an empty line.

  "dsh-statusline-guard" =
    pkgs.runCommand "check-dsh-statusline"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.git
          pkgs.jq
        ];
      }
      ''
        export HOME="$TMPDIR/home"
        mkdir -p "$HOME"
        bash ${../scripts/dev/check-dsh-statusline.sh} ${../packages/local-bin/bin/dsh-statusline}
        touch $out
      '';

  # ── nix-maid app directory guard ───────────────────────────────────
  # modules/user/nix-maid/apps/default.nix auto-imports every sibling directory
  # as a module and keeps an explicit filter list for the data and plugin-bundle
  # directories. A plugin directory missing from that list breaks the whole
  # system *evaluation*:
  #   error: Path '.../apps/<name>/default.nix' does not exist in Git repository
  # which reads like a flake/git problem and only surfaces during a rebuild.
  # The guard makes the rule fast and local, and names the line to add.

  "nix-maid-app-dirs-guard" =
    pkgs.runCommand "check-nix-maid-app-dirs"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
          pkgs.gnugrep
          pkgs.gnused
        ];
      }
      ''
        bash ${../scripts/dev/check-nix-maid-app-dirs.sh} ${../modules/user/nix-maid/apps}
        touch $out
      '';

  # ── NixOS test config checks ───────────────────────────────────────
  # Each evaluates a profile-specific NixOS configuration for "odin"
  # via mkTestHost (threaded from flake.nix; stripped from the
  # nixosConfigurations output so flake-schemas sees a pure machine set).
  # These ensure the A/B test configurations evaluate without errors.

  "test-odin-gaming" =
    let
      cfg = mkTestHost "odin" "gaming";
    in
    pkgs.runCommand "check-test-odin-gaming" { } ''
      echo "check: test-odin-gaming OK (${toString (builtins.length (builtins.attrNames cfg.options))} options)"
      touch $out
    '';
}
