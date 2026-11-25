# Checks for parallel evaluation via nix-eval-jobs.
#
# Each check exercises an independent subset of the NixOS module tree.
# nix-eval-jobs dispatches every flake output attribute as a separate job,
# so adding checks here creates additional parallel eval units that run
# alongside nixosConfigurations, devShells, etc.
#
# Domain filter refactoring (Jul 2026):
#   modules/default.nix now accepts domainFilter via specialArgs, letting
#   evalModules checks restrict which module domains are imported (smaller
#   eval trees) while still using the host's filter.
# ---------------------------------------------------------------------------
{
  nixpkgs,
  self,
  mkSpecialArgs,
  ...
}:
pkgs:
let
  inherit (nixpkgs) lib;

  # Module arguments for the evalModules-based checks, built by the same
  # function the real hosts use (flake/nixos.nix mkSpecialArgs). The previous
  # hand-kept copy had drifted: no `opts`, `iosevkaNeg = { }` and a raw `self`
  # as `filteredSource`. `pkgs` is added here because lib.evalModules, unlike
  # lib.nixosSystem, does not inject it.
  mkStubArgs =
    domainFilter:
    mkSpecialArgs
    // {
      inherit domainFilter pkgs;
    };

  # Eval-only unit checks (lib/*-tests.nix) return { failures, checks, report }.
  # A clean run becomes a trivial runCommand; a failure aborts evaluation.
  mkOkCheck =
    name: t:
    if t.failures == [ ] then
      pkgs.runCommand "check-${name}" { } ''
        echo "check: ${name} OK (${toString (builtins.length t.checks)} assertions)"
        touch $out
      ''
    else
      builtins.throw "${name} check failures: ${t.report}";

  # Shared shape of the script gates below: bash and coreutils are always in
  # the environment, `deps` adds what the script itself shells out to, and the
  # caller splices the script body (it still owns any tree copies it needs).
  mkScriptCheck =
    name: deps: script:
    pkgs.runCommand "check-${name}"
      {
        nativeBuildInputs = [
          pkgs.bash
          pkgs.coreutils
        ]
        ++ deps;
      }
      ''
        ${script}
        touch $out
      '';

in
{
  # ── Unit checks (pure nix, eval-only) ──────────────────────────────
  # lib/ru-keys.nix is the single source of truth for ЙЦУКЕН hotkey
  # duplicates; these assertions pin the table and every generator.
  "ru-keys" = mkOkCheck "ru-keys" (import ../lib/ru-keys-tests.nix { lib = nixpkgs.lib; });
  # kitty configs: every map carries --allow-fallback=shifted,ascii (that is what
  # serves the ru layout), action lines have no inline comments (kitty passes
  # everything after the action to it as arguments) and stay ASCII-only.
  "kitty-config" = mkOkCheck "kitty-config" (
    import ../lib/kitty-config-tests.nix { lib = nixpkgs.lib; }
  );

  # ── fzf opts guards ────────────────────────────────────────────────
  # fzf parses FZF_*_OPTS values as its own CLI options; a standalone '#'
  # token silently truncates them (regression: commit 5cd4942a dropped all
  # colors/binds). fzf-opts-guard pins the predicate, fzf-opts parses the
  # real trantor values with fzf itself.

  "fzf-opts-guard" = mkOkCheck "fzf-opts-guard" (import ../lib/fzf-opts-tests.nix);

  # ── disabledModules guard ─────────────────────────────────────────
  # nixpkgs matches an entry against module keys as a string and silently
  # ignores a miss, so a module that moved upstream stops being disabled while
  # the list still looks intentional. The suite resolves every entry against
  # the pinned nixpkgs (and rejects duplicates); see
  # lib/disabled-modules-tests.nix.

  "disabled-modules" = mkOkCheck "disabled-modules" (
    import ../lib/disabled-modules-tests.nix { inherit nixpkgs; }
  );

  # ── neg-helpers by-name resolver guard ─────────────────────────────
  # neg.tree / neg.find back the "address a file by name" convention, and
  # modules/default.nix no longer lists a single domain path (nameFilter does
  # the domain selection). The guard pins the conventions: extension stripping,
  # default.nix addressing its own directory, "_"-prefixed entries being
  # private, find throwing on a miss, nameFilter dropping by name.

  "neg-tree-guard" = mkOkCheck "neg-tree-guard" (import ../lib/neg-helpers-tests.nix);

  # ── feature flag guard ─────────────────────────────────────────────
  # `lib.neg.enabled "<path>"` reads features.<path>.enable; a path no module
  # declares silently reads false, so the gate dies quietly instead of failing
  # (regression: security.lockKernelModules was declared without `.enable`).
  # The option tree comes from the real host config, the paths from a text scan
  # of modules/ + hosts/ (lib/feature-flags-tests.nix).

  "feature-flags" =
    let
      # Options of the full feature tree (not of one host: trantor's domain set
      # excludes some domains, e.g. `apps`, whose flags are still legitimate).
      featuresOptions =
        (lib.evalModules {
          specialArgs = mkStubArgs (_: true);
          modules = [
            { _module.check = false; }
            # core provides the module args the feature modules take (mkBool);
            # features declares the option tree itself.
            ../modules/core/default.nix
            ../modules/features
          ];
        }).options.features;
    in
    mkOkCheck "feature-flags" (
      import ../lib/feature-flags-tests.nix {
        inherit lib featuresOptions;
      }
    );

  "fzf-opts" =
    let
      vars = self.nixosConfigurations.trantor.config.environment.variables;
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

  # ── lib.sh self-test ───────────────────────────────────────────────
  # scripts/dev/lib.sh is sourced by every lint gate and by the checks below, and
  # scripts/dev/lib.test.sh pins its helpers (11 assertions: repo_root, pmap,
  # platform detection). Nothing ran the test, so the gate is the fix: a broken
  # helper now fails `just check` instead of surfacing as a mysterious lint
  # failure later.

  "lib-self-test" = mkScriptCheck "lib-self-test" [ ] ''
    # Splice the whole scripts/dev dir so the test finds lib.sh next to itself.
    bash ${../scripts/dev}/lib.test.sh
  '';

  # ── dsh-worktree guard ─────────────────────────────────────────────
  # rust-pkgs/local-bin-tools' dsh-worktree creates real git worktrees outside
  # the repository so parallel dsh sessions never fight over the working copy. The
  # guard pins the contract: trees stay out of the main checkout's `git status`,
  # each carries its own branch, and a dirty tree is not removed without
  # --force. It runs against a throwaway repository in $TMPDIR.

  "dsh-worktree-guard" = mkScriptCheck "dsh-worktree" [ pkgs.git ] ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    # Splice the whole scripts/dev dir so the gate finds lib.sh next to itself.
    bash ${../scripts/dev}/check-dsh-worktree.sh ${pkgs.neg.local-bin-tools}/bin/dsh-worktree
  '';

  # ── dsh-statusline guard ───────────────────────────────────────────
  # rust-pkgs/local-bin-system (dsh-statusline) is the content half of the status
  # line: session JSON on stdin, one line on stdout. The guard pins the protocol
  # subset (branch, dirty counts, context from ratio or tokens/max, turn), the
  # worktree naming, DSH_STATUSLINE_PARTS, and that a missing field degrades
  # instead of printing an empty line.

  "dsh-statusline-guard" = mkScriptCheck "dsh-statusline" [ pkgs.git pkgs.jq ] ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME"
    # Splice the whole scripts/dev dir so the gate finds lib.sh next to itself.
    bash ${../scripts/dev}/check-dsh-statusline.sh ${pkgs.neg.local-bin-system}/bin/dsh-statusline
  '';

  # ── nix wrapper guard ──────────────────────────────────────────────
  # packages/local-bin/bin/nix is the ~/.local/bin shim that keeps `nix …` usable
  # inside the DSH workspace-write sandbox, where $HOME is read-only and nix
  # cannot open its fetcher locks under ~/.cache/nix. The guard pins the
  # conditionality (a writable cache root stays untouched), the argument
  # passthrough, the warning when no scratch cache is usable, and the 127 on a
  # missing real binary — a shim that silently swallows nix would be worse than
  # the original error.

  "nix-wrapper-guard" = mkScriptCheck "nix-wrapper" [ ] ''
    # Splice the whole scripts/dev dir so the gate finds lib.sh next to itself.
    bash ${../scripts/dev}/check-nix-wrapper.sh ${../packages/local-bin/bin/nix}
  '';

  # ── nix-maid app directory guard ───────────────────────────────────
  # modules/user/nix-maid/apps/default.nix imports sibling directories via
  # neg.importDir { includeDirs = true; }, which skips any directory without a
  # default.nix. That makes data and plugin-bundle directories safe by default
  # (no deny-list). The guard pins the contract: the importDir call, and the
  # default.nix existence check inside lib/neg-helpers.nix that backs the skip.
  # A hand-rolled builtins.readDir filter would import every entry and break
  # evaluation with "Path '.../apps/<name>/default.nix' does not exist".

  "nix-maid-app-dirs-guard" = mkScriptCheck "nix-maid-app-dirs" [ pkgs.gnugrep ] ''
    # Splice the whole scripts/dev dir so the gate finds lib.sh next to itself.
    bash ${../scripts/dev}/check-nix-maid-app-dirs.sh \
      ${../modules/user/nix-maid/apps} \
      ${../lib/neg-helpers.nix}
  '';

  # ── Relative-path guard ────────────────────────────────────────────
  # modules/, hosts/ and packages/ reach repo files through config.lib.neg.*,
  # neg.rooted, the injected `paths` resolver or neg.functions.pkg — never by
  # counting `../..` segments, which break when the file *or* the caller moves
  # and say nothing about what they point at. The guard runs the same script
  # `just lint` runs, on a copy of the three trees, and accepts a deliberate
  # exception only via a `# allow-relative: <reason>` /
  # `# allow-relative-file: <reason>` marker.

  # `nix flake check` evaluates the flake outputs but not every package's
  # derivation graph; force each drvPath so a broken callPackage in packages/
  # fails the check set instead of waiting for the first build.
  "packages-eval" =
    let
      system = pkgs.stdenv.hostPlatform.system;
      packages = self.packages.${system};
    in
    builtins.deepSeq (builtins.mapAttrs (_: p: p.drvPath) packages) (
      pkgs.runCommand "check-packages-eval" { } ''
        echo "check: ${toString (builtins.length (builtins.attrNames packages))} flake packages evaluate"
        touch $out
      ''
    );

  # lib/package-checks.nix gates alias generation on package availability; a
  # renamed package silently drops the alias (btm -> bottom was exactly that).
  # Force every guard and fail on a stale one.
  "package-checks" =
    let
      guards = import ../lib/package-checks.nix { inherit pkgs; };
      missing = builtins.filter (name: !guards.${name}) (builtins.attrNames guards);
    in
    if missing == [ ] then
      pkgs.runCommand "check-package-checks" { } ''
        echo "check: all ${toString (builtins.length (builtins.attrNames guards))} package guards resolve"
        touch $out
      ''
    else
      throw "stale package guards in lib/package-checks.nix: ${builtins.concatStringsSep ", " missing}";

  "relative-paths-guard" = mkScriptCheck "relative-paths" [ pkgs.findutils pkgs.gawk ] ''
    mkdir -p "$TMPDIR/repo"
    cp -r ${../modules} "$TMPDIR/repo/modules"
    cp -r ${../hosts} "$TMPDIR/repo/hosts"
    cp -r ${../packages} "$TMPDIR/repo/packages"
    bash ${../scripts/dev}/check-relative-paths.sh "$TMPDIR/repo"
  '';

  # Same class, the other absolute: `$HOME`-relative paths written as
  # /home/<user> instead of config.lib.neg.homeDir (modules, hosts, lib).
  "absolute-home-guard" = mkScriptCheck "absolute-home" [ pkgs.findutils pkgs.gawk ] ''
    mkdir -p "$TMPDIR/repo"
    cp -r ${../modules} "$TMPDIR/repo/modules"
    cp -r ${../hosts} "$TMPDIR/repo/hosts"
    cp -r ${../lib} "$TMPDIR/repo/lib"
    bash ${../scripts/dev}/check-absolute-home.sh "$TMPDIR/repo"
  '';

  # ── Text gates from `just lint`, promoted into the flake ────────────
  # Same scripts the lint recipe runs; wired here so `nix flake check`
  # (the CI entry point) covers them too instead of relying on just.
  # Each cd into the root they are given and only need grep (the palette
  # gate also runs the dircolors file through the real parsers).

  "package-annotations-guard" = mkScriptCheck "package-annotations" [ pkgs.gnugrep ] ''
    mkdir -p "$TMPDIR/repo"
    cp -r ${../modules} "$TMPDIR/repo/modules"
    bash ${../scripts/dev}/check-package-annotations.sh "$TMPDIR/repo"
  '';

  "hyprland-vars-guard" = mkScriptCheck "hyprland-vars" [ pkgs.gnugrep ] ''
    mkdir -p "$TMPDIR/repo/files/gui"
    cp -r ${../files/gui/hypr} "$TMPDIR/repo/files/gui/hypr"
    bash ${../scripts/dev}/check-hyprland-vars.sh "$TMPDIR/repo"
  '';

  # The shell palette gate feeds the dircolors file to the real parsers as well
  # as comparing the two colour tables. A line they reject — a bare `bashrc` or
  # `@.service` — leaves LS_COLORS empty in every fresh shell: uutils aborts the
  # whole file, GNU silently drops the line, and the guard's own awk parser
  # skipped both, so nothing failed until a new terminal window came up
  # colourless. Both binaries are passed in *and required*, so the gate cannot
  # degrade to a no-op if an attribute moves.
  "shell-palette" = mkScriptCheck "shell-palette" [ pkgs.gnugrep pkgs.gawk ] ''
    mkdir -p "$TMPDIR/repo/files/shell/dircolors"
    cp ${../files/shell/dircolors/dircolors} "$TMPDIR/repo/files/shell/dircolors/dircolors"
    cp -r ${../files/shell/zsh-native-syntax} "$TMPDIR/repo/files/shell/zsh-native-syntax"
    DIRCOLORS_PARSERS="${pkgs.coreutils}/bin/dircolors:${pkgs.uutils-coreutils-noprefix}/bin/dircolors" \
      DIRCOLORS_PARSERS_REQUIRED=1 \
      bash ${../scripts/dev}/check-shell-palette.sh "$TMPDIR/repo"
  '';
}
