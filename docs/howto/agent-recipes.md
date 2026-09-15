# Agent Recipes — Verified Task Patterns

Hands-on, verified recipes for the most common changes to this repo. Every step was cross-checked
against the current tree (paths, option names, lint rules). If a recipe contradicts what you
actually see in the tree, the recipe is wrong — fix the recipe, don't work around it.

Orientation first: `docs/codebase.md` (generated, regenerate with `just codebase`) maps the
structure — feature flags, module domains, packages, overlay wiring.

## 0. Golden rules (apply to every change)

- Keep diffs minimal and focused (root `AGENTS.md`).
- Add an inline `# comment` after every `pkgs.*` entry in package lists — enforced by `just lint`
  (`scripts/dev/check-package-annotations.sh`).
- Commit subject: `[scope] imperative short summary` — ASCII only, no trailing period (enforced by
  the `commit-msg` hook; scope examples: `[dev/pkgs]`, `[hosts/odin]`, `[docs]`).
- The `pre-commit` hook runs the **full lint suite** inside `nix develop .#lint --command just lint`
  — slow on first run (builds the devshell). Run `just lint` locally before committing.
- Shell syntax is guarded with `osh -n` (`scripts/dev/check-osh-syntax.sh`): every tracked shell
  script must parse under Oils' bash-compatible parser. Runtime-only incompatibilities are NOT
  caught by `-n` (e.g. bare assoc-array keys, `read -t` with a non-zero timeout) — keep those out by
  convention; see the quoted-key fix in `files/art/fun-art/bonsai.sh`.
- Hooks live in `.githooks/`; enable with `just hooks-enable`
  (`git config core.hooksPath .githooks`).

## 1. Add a NixOS module

**Goal:** new system-level functionality inside an existing module domain.

**Touch:**

- `modules/<domain>/<name>.nix` — flat file; the domain's `default.nix` auto-imports it via
  `neg.importDir` (no registration needed)
- or `modules/<domain>/<sub>/default.nix` — subdirectory module
- new **top-level** domain → also register in `modules/default.nix`:
  `domain "name" ./name/default.nix`

**Steps:**

1. Pick the domain (see `modules/README.md` or the `## Module domains` section of
   `docs/codebase.md`).

1. Create the module and gate it on its feature flag:

   ```nix
   { lib, config, pkgs, ... }:
   lib.mkIf (config.features.<domain>.<feature>.enable or false) {
     environment.systemPackages = [
       pkgs.<pkg> # short comment: what the package does
     ];
   }
   ```

1. Define the flag if it doesn't exist yet (recipe 3).

1. Refresh docs: `just codebase`; update `OPTIONS.md` (manual, tracked) if options changed.

**Example:** `modules/dev/omp.nix` — gates `features.dev.ai.omp.enable`, wraps the omp binary,
installs via `environment.systemPackages`.

**Verify:** `just check` (`nix flake check -L`), or dry-build the host closure:
`nix build .#nixosConfigurations.odin.config.system.build.toplevel`.

**Gotchas:** `lib` must be in the function args for `mkIf`; never write `with pkgs; [...]` (lint
guard); scripts needed by systemd units should not `mkdir`/`touch`/`rm` in `ExecStart*` — prefer
`neg.mkLocalBin` or a `writeShellScriptBin` wrapper (lint guard).

## 2. Reference repo files by root path (`config.lib.neg.path`)

**Goal:** point at a file under `files/`, `secrets/`, `lib/`, or `packages/…` without
`../../../../../` chains that break when a module moves.

**Touch:** only the module that references the file.

**Steps:**

1. In the module, use `config.lib.neg.path "<repo-relative>"` wherever a path was built with `../`:

   ```nix
   { config, ... }:
   {
     environment.etc."greetd/quickshell".source = config.lib.neg.path "files/quickshell";
     sops.secrets."x".sopsFile = config.lib.neg.path "secrets/home/x.sops.yaml";
   }
   ```

   `path` resolves against `options.neg.repoRoot` (defaults to the flake `self` source, so it works
   regardless of where the repo is checked out — also in `flake/checks.nix` stub args).

1. Keep **sibling** imports relative (`../scripts/…`, `../mutt-conf`): `path` is for jumps to the
   repo root only.

1. Do **not** convert a `mkDerivation` `src` to `path` — a derivation input must stay a real path
   (string breaks store-input tracking). Keep `src = ./relative/…` there.

**Verify:**
`nix build .#nixosConfigurations.odin.config.system.build.toplevel --dry-run --option substitute false`
(a bad path fails evaluation).

## 3. Add a feature flag

**Touch:**

- `modules/features/<domain>.nix` — flag definitions (dir is auto-imported)
- `modules/features/default.nix` — optional `assertParent` cross-checks
- `OPTIONS.md` — manual refresh (root, tracked)

**Steps:**

1. Toggle:

   ```nix
   enable = mkBool "description" false;
   ```

   or value option:

   ```nix
   lib.mkOption {
     type = types.str;
     default = "value";
     description = "description";
   };
   ```

1. Nested paths: `sub = { enable = mkBool "..." false; };` → flag is `features.<domain>.sub.enable`.

1. If a child requires its parent flag, add an assertion in `modules/features/default.nix`:

   ```nix
   (assertParent parentCond childCond "message")
   ```

   (see the existing `features.gui.qt.enable` / `features.gui.vicinae.enable` assertions).

1. Enable per host: `hosts/<host>/default.nix` → `features.<domain>.<feature>.enable = true;` (add a
   `# comment` when non-obvious), or per profile: `modules/profiles/<name>.nix` →
   `features.<domain>.<feature>.enable = mkDefault true;`.

1. Refresh: update `OPTIONS.md`, run `just codebase`.

**Example:**
`features.dev.ai.omp.enable = mkBool "install Oh My Pi (omp) AI coding agent (fork of Pi)" false;`
in `modules/features/dev.nix`, enabled in `hosts/odin/default.nix`.

**Verify:** `rg "features.<domain>.<feature>" modules/ hosts/` shows definition, host/profile
enablement, and consumer; `just codebase` lists the flag with its default and description.

## 4. Add a package

**Touch:**

- `packages/<name>/default.nix` — the derivation
- `packages/overlays/<domain>.nix` — expose as `pkgs.neg.<name>`
- `packages/flake/custom-packages.nix` — optional: expose for `nix build .#<name>`
- a module's `environment.systemPackages` — to actually install it

**Steps:**

1. Create `packages/<name>/default.nix` in its own directory; fill `meta` (`description`,
   `homepage`, `license`, `platforms`, `maintainers`) and keep fetcher hashes current — fetch the
   new hash with `nix-prefetch-url` (or `nix store prefetch-file`) and paste it into the
   `hash`/`cargoHash`/`vendorHash` field.

1. Wire into the right domain overlay (`functions`/`tools`/`media`/`dev`/`gui`; see
   `packages/overlays/README.md`). Follow the local style of that file:

   ```nix
   # packages/overlays/tools.nix (has a callPkg helper with packagesRoot)
   myapp = callPkg (packagesRoot + "/myapp") { }; # short role comment
   ```

   Other files use `callPkg (inputs.self + "/packages/myapp") { }` (gui.nix) or
   `prev.callPackage ../myapp { }` (media.nix).

1. To install: add to `environment.systemPackages` in the fitting module, with an inline `# comment`
   (annotation lint). Optionally gate with a feature flag.

1. For `nix build .#<name>`: add `myapp = pkgs.neg.myapp; # comment` to
   `packages/flake/custom-packages.nix`.

**Example:** `packages/omp/default.nix` (npm tarball → bun wrapper), wired in
`packages/overlays/tools.nix` (`omp = callPkg (packagesRoot + "/omp") { };`), flag in
`modules/features/dev.nix`.

**Verify:** `nix build .#<name>`; `just check`; `just lint` (annotations).

**Gotchas:** native addons need `makeWrapper --prefix LD_LIBRARY_PATH : ...` (see
`packages/omp/libstdcxx-fix.md` for the full diagnosis); npm postinstalls that fetch binaries →
`npmInstallFlags = [ "--ignore-scripts" ]` + `--ignore-scripts` on rebuild; every `pkgs.*` list
entry needs a `# comment`.

## 5. Add a host

**Touch:**

- `hosts/<name>/default.nix` (+ `hardware.nix`, `networking.nix`, `services/`)
- `flake/nixos.nix` — register the host in the output set
- optional `hosts/<name>/extra.nix` — host-only modules (auto-included)

**Steps:**

1. Create `hosts/<name>/`; `default.nix` imports the host files and sets `features.profiles` (order
   matters — later profiles win). See `hosts/odin/default.nix` as the reference.

1. Register in `flake/nixos.nix`:

   ```nix
   "<name>" = mkHost "<name>";
   ```

   (`hostsDir = ../hosts`; `mkHost` imports `hosts/<name>`; non-odin hosts get the `allDomains`
   domain filter automatically.)

1. Add the host to `hosts/README.md` table.

**Verify:** `just check`; `nix build .#nixosConfigurations.<name>.config.system.build.toplevel`.

**Gotchas:** `hosts/README.md` says "add to `flake.nix`" — the real registration lives in
`flake/nixos.nix`; `mkTestHost` (same file) is for A/B profile tests in `flake/checks.nix`, not for
normal hosts.

## 6. Add a `~/.local/bin` script (local-bin)

**Goal:** a small personal CLI available in `$PATH`.

**Touch:** `packages/local-bin/bin/<name>` or `packages/local-bin/scripts/<name>`

**Steps:**

1. Drop an executable file (bash or python3 shebang). It is auto-installed to `~/.local/bin/<name>`
   by `modules/user/nix-maid/cli/local-bin.nix` (requires `features.gui.enable`).
1. Keep dependencies minimal — stdlib, or packages already in the environment.
1. Runtime Nix store paths must go through the per-file substitution pattern in
   `modules/user/nix-maid/cli/local-bin.nix` (see `ren`/`vid-info.py` with `@LIBPP@`/`@LIBCOLORED@`,
   `kitty-scrollback-nvim` with `@NIX_KSB_PATH@`).
1. Naming: extensionless python files avoid the `*.py` lint path (`just lint` runs ruff/black only
   on `*.py`); `.sh`/`.bash` files are shellchecked when they carry a bash shebang.

**Example:** `packages/local-bin/bin/gen-codebase` — generates `docs/codebase.md`; run from anywhere
(resolves the repo root via git).

**Verify:** `~/.local/bin/<name>` exists after rebuild and behaves; `just lint` stays clean.

**Gotchas:** don't hardcode Nix store paths in scripts — add a substitution case in local-bin.nix
instead; scripts meant for the system (not the user) belong in a package or `neg.mkLocalBin`, not
local-bin.

## 7. Add a sops secret

**Touch:** `secrets/<path>.sops.yaml` (or a raw `.sops` file) + `sops.secrets.*` in a module/host.

**Steps:**

1. Create/edit with the repo's `.sops.yaml` rules:

   ```sh
   sops secrets/home/<name>.sops.yaml        # opens editor, creates + encrypts
   ```

   Editing an existing file re-encrypts in place on save (see `docs/runbook-proxy.md` for a full
   example).

1. Wire it in NixOS (sops-nix module is already in `commonModules`, `flake/nixos.nix`). Two patterns
   used in this repo:

   ```nix
   # yaml file with a key (most common)
   sops.secrets."<key>" = {
     sopsFile = ./secrets/home/<name>.sops.yaml;
     owner = "neg";
     key = "<yaml_key>";
   };

   # raw/binary file (whole file is the secret)
   sops.secrets."<key>" = {
     sopsFile = ./secrets/home/<name>.sops;
     format = "binary";
     owner = "neg";
   };
   ```

   `mode`/`owner` default sensibly; `sops.useTmpfs = true` is set repo-wide
   (`modules/nix/settings.nix`) — don't rely on ramfs paths for activation.

1. Runtime path: `config.sops.secrets.<key>.path` → `/run/secrets/<key>`.

**Example:** `hosts/odin/default.nix` →
`users.main.hashedPasswordFile = config.sops.secrets."user-password-hash".path;` backed by
`secrets/home/user-password-hash.sops.yaml` (yaml+key); raw pattern:
`modules/user/nix-maid/sys/media.nix` → `lastfm/rescrobbled` from
`secrets/home/lastfm-rescrobbled.sops` (`format = "binary"`).

**Verify:** locally `sops --decrypt secrets/home/<name>.sops.yaml`; on the machine after deploy:
`cat /run/secrets/<key>`.

**Gotchas:** never commit plaintext secrets; keep secret *references* out of modules where possible
(root `AGENTS.md`); raw files get `format = "binary"`, yaml files get `key` — don't mix the two.

## 8. Update docs

- Cross-link new documents from `docs/index.md` (and `docs/howto/index.md` for how-tos) — required
  by `docs/AGENTS.md`.
- Docs are English-only (hard rule, root `AGENTS.md`): no `*.ru.md` variants, no Russian prose in
  docs; the markdown-language check fails on Cyrillic/CJK in any `*.md` file.
- Generated docs: `just docs-modules` → `docs/howto/modules.md`; `just codebase` →
  `docs/codebase.md`. `OPTIONS.md` is maintained manually.
- Placement: `docs/howto/` — focused guides/reference; `docs/runbook-*.md` — operational steps; add
  new topics to `docs/index.md` / `docs/howto/index.md`.

## 9. Verify & deploy

- `just fmt` — format everything (nixfmt, shfmt, black, mdformat, taplo)
- `just lint` — full lint suite (statix, deadnix, ruff/black, shellcheck,
  QML/Hyprland/markdown/syntax checks, package annotations)
- `just check` — `nix flake check -L`
- `just deploy [host]` — build + switch (default `odin`); `just deploy-nh` — nh-based alternative;
  `just deploy-debug` — verbose
- dry-run before touching the system:
  `nix build .#nixosConfigurations.<host>.config.system.build.toplevel`
- `nix flake check` does **not** force derivations, so a lazy eval error can pass the checks and
  fail the switch. Force the toplevel drv as well:
  `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`

## 10. Commit

1. `git add` only the touched files.
1. Subject: `[scope] imperative short summary` — ASCII only, no trailing period (commit-msg hook
   enforces both).
1. The `pre-commit` hook runs the full lint in the `.#lint` devshell; if the devshell isn't built
   yet, the first commit is slow — that's normal.
1. Hooks inactive? Run `just hooks-enable`.

## 11. Extract an inline Nix string block into a file

**Goal:** move a `''...''` block (build phase, script body, config, rule set) out of a `.nix` file
into a real file without changing behaviour. Verified across the repo (31 commits): every extracted
block was A/B-checked against the old evaluated text.

**Where the file goes**

- config/rule/data sets → `files/<area>/<name>`, read through `config.lib.neg.path "files/..."` (see
  recipe 2). Module directories without a `default.nix` are skipped by `neg.importDir`, so script
  files can live next to a module.
- module-local script body → next to the module (`modules/<domain>/<name>.sh`, no shebang: the
  `writeShellScript*` wrapper still adds it).
- package build phase → next to the package (`packages/<pkg>/install.sh`, `post-install.sh`).
- placeholder template that treefmt would reflow **and** that must stay byte-identical → keep a
  non-`.sh` suffix (e.g. `post-patch.sh.in`) so shfmt skips it. Any byte change to a phase text
  flips the derivation hash; that is how a cosmetic edit triggers a ROCm-sized rebuild.

**How to read it back**

```nix
builtins.readFile (config.lib.neg.path "files/<area>/<name>") # plain text
builtins.replaceStrings [ "@FOO@" ] [ foo ] (builtins.readFile ./x.sh) # with substitutions
```

Use `builtins.replaceStrings`, **not** `pkgs.replaceVars`, when the text is a build phase or a
substituted value has to be reachable at build time:

- a phase must stay a **string**: a store path (what `pkgs.replaceVars` returns) is executed as a
  separate process, so `runHook` and setup hooks such as `makeWrapper` do not exist in it;
- `pkgs.replaceVars` drops the store context of a **path** value (`lib.escapeShellArg` → `toString`,
  and `toString` of a path carries no context: `builtins.hasContext "${path}"` is true while
  `builtins.hasContext (toString path)` is false), so a phase that `cp`s or `exec`s that path fails
  in the sandbox with "No such file or directory";
- `builtins.replaceStrings` preserves context, so the derivation keeps its inputs.

`pkgs.replaceVars` remains the right tool for text that is only *written* (for example the `text` of
`writeShellApplication`), which is the pattern used across `modules/`.

**Translating the block (Nix indented-string rules)**

1. drop the first newline and the final `\n<indent>` before the closing `''`;
1. strip the common indentation from **every** line — whitespace-only lines included (Nix strips
   their prefix too; forgetting this leaves stray spaces in the file);
1. unescape `''${` → `${`, `'''` → `''`, `''\n`, `''\t`, `''\\`;
1. replace each `${expr}` with `@NAME@` using brace counting (escape sequences first, then
   interpolations);
1. leave `@NAME@` tokens that the block itself consumes (e.g. mojo's `@PYTHON@`, replaced by an
   in-phase `sed`) out of the replacement set — `builtins.replaceStrings` ignores them, while
   `pkgs.replaceVars` fails the build on any unmatched `@[A-Za-z_][0-9A-Za-z_'-]*@`;
1. wrap substituted values that are paths or derivations as `"${...}"`: a bare `pkgs.a-b` value
   reaches `replaceStrings` as a derivation set ("expected a string but found a set");
1. parenthesise the whole expression when it sits in an argument position
   (`runCommandLocal "x" { } (<expr>)`, `writeText "x" (<expr>)`), otherwise Nix keeps reading the
   remaining arguments as further parameters of the call.

**Verify**

- the extracted file must equal the old evaluated text: for a phase compare
  `nix derivation show <drv>` → `derivations.<drv>.env.installPhase`; for an option compare the
  `nix eval` value. Byte-exact for config/rule/Lua files, `shfmt -i 2 -ci -bn -sr`-normalised for
  `.sh` files (treefmt reformats those, that is the only accepted difference);
- A/B the evaluation: `git stash push` the touched files, capture the old values
  (`nix eval --json --apply '...' .#nixosConfigurations.odin.config`), `git stash pop`, then diff.
  For home files compare `config.users.users.neg.maid.file.home` (all ~340 entries) — this catches
  stray whitespace and wrong substitutions;
- an unchanged derivation is the strongest signal: the same `drvPath` (or the same output store path
  in the new generation) means the text is byte-identical;
- before rolling out, force the toplevel:
  `nix eval --raw .#nixosConfigurations.<host>.config.system.build.toplevel.drvPath`.
  `nix flake check` evaluates the configuration but does **not** force derivations, so lazy eval
  errors (like the dashed-path one above) surface only at rollout time.
