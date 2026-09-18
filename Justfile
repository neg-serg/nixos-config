# Repository development helpers for NixOS workflows
set shell := ["bash", "-cu"]

# Repository root for the repo-wide recipes. Every recipe run evaluates this
# backtick, so it falls back to the invocation dir when not in a git repo.
repo_root := `git rev-parse --show-toplevel 2>/dev/null || pwd`

# --- System Management -----------------------------------------------------------

# Rebuild and switch to the new system configuration
# Usage: just deploy [host]
deploy host="odin":
    # Build system closure with network tuning
    nix build .#nixosConfigurations.{{ host }}.config.system.build.toplevel \
      --out-link result \
      --option connect-timeout 60 \
      --option download-attempts 2 \
      --option stalled-download-timeout 600 \
      --option substitute false

    # Update system profile
    sudo nix-env -p /nix/var/nix/profiles/system --set $(readlink -f result)
    # Switch to new configuration
    sudo ./result/bin/switch-to-configuration switch

# Deploy (Legacy/Slow) - keeps nh features like pretty print
deploy-nh host="odin":
    nh os switch . --hostname {{ host }} --option substitute false

# Deploy with maximum verbosity (logs + trace + verbose)
deploy-debug host="odin":
    nh os switch . --hostname {{ host }} -L -t -v --option substitute false

# Alias for deploy
switch host="odin":
    just deploy {{ host }}

# Show diff between last two generations
diff:
    @files=$(find /nix/var/nix/profiles -maxdepth 1 -name "system-*-link" | sort -V | tail -n 2); \
    nix run nixpkgs#dix -- $files

# Copy the live lazy.nvim lockfile (~/.local/state) into the repo snapshot.
# Run after :Lazy sync in nvim; shows the diff, then commit manually.
nvim-lock-sync:
    cp "$HOME/.local/state/nvim/lazy-lock.json" files/nvim/lazy-lock.json
    git diff --stat -- files/nvim/lazy-lock.json

# --- Repo-wide workflows ---------------------------------------------------------
fmt:
    cd "{{repo_root}}" && nix fmt

check:
    nix flake check -L --option substitute false

lint:
    set -eu
    statix check -- .
    deadnix --fail .
    # Guard: discourage `with pkgs; [ ... ]` lists (prefer explicit pkgs.*)
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'with[[:space:]]+pkgs;[[:space:]]*\[' . | grep -q .; then \
      echo 'Found discouraged pattern: use explicit pkgs.* items instead of `with pkgs; [...]`' >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'with[[:space:]]+pkgs;[[:space:]]*\[' . || true; \
      exit 1; \
    fi; \
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'targetPkgs[[:space:]]*=[[:space:]]*pkgs:[[:space:]]*with[[:space:]]+pkgs' . | grep -q .; then \
      echo 'Found discouraged pattern in FHS targetPkgs: avoid `with pkgs`' >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'targetPkgs[[:space:]]*=[[:space:]]*pkgs:[[:space:]]*with[[:space:]]+pkgs' . || true; \
      exit 1; \
    fi
    # Guard: avoid mkdir/touch/rm in ExecStartPre/ExecStart within systemd units —
    # declare managed files (per-file `force = true`) or wrappers instead.
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
         'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules | \
       grep -q .; then \
      echo 'Found ExecStartPre/ExecStart with mkdir/touch/rm. Declare managed files (force = true) or wrappers instead.' >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
        'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules || true; \
      exit 1; \
    fi
    # Guard: avoid `with pkgs.lib` — use explicit pkgs.lib.*
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.lib\b' . | grep -q .; then \
      echo "Found discouraged pattern: avoid 'with pkgs.lib'; use explicit pkgs.lib.*" >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.lib\b' . || true; \
      exit 1; \
    fi
    # Guard: avoid generic `with pkgs.<ns>` — prefer explicit pkgs.<ns>.<item>
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.[A-Za-z0-9_-]+' . | grep -v -E 'pkgs\.lib\b' | grep -q .; then \
      echo "Found discouraged pattern: avoid 'with pkgs.<ns>'; reference explicit pkgs.<ns>.<item>" >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.[A-Za-z0-9_-]+' . | grep -v -E 'pkgs\.lib\b' || true; \
      exit 1; \
    fi
    # `&&` so a failing ruff fails this line: the recipe runs under `bash -cu`
    # (no -e) and a plain `;` would let black's success mask it.
    if git ls-files -- '*.py' >/dev/null 2>&1; then \
      ruff check -- . && \
      black --check --line-length 79 --extend-exclude '(files/kitty|files/art/fun-art|files/x11/rice|files/x11/decay-gtk)' .; \
    fi
    # TOML syntax/style — tracked files only: a bare `taplo lint` follows result/
    # into the nix store (pyright's typeshed alone is ~200 METADATA.toml) plus the
    # local nix/ dump, for ~1s of pointless walking; RUST_LOG=warn hides taplo's
    # file-list INFO line.
    if command -v taplo >/dev/null 2>&1; then git ls-files -z -- '*.toml' 2>/dev/null | RUST_LOG=warn xargs -0 -r taplo lint; else echo "taplo not found — skipping TOML lint"; fi
    # Rust formatting (edition-aware via nearest Cargo.toml)
    if command -v rustfmt >/dev/null 2>&1; then bash scripts/dev/check-rustfmt.sh; else echo "rustfmt not found — skipping Rust check"; fi
    # Optional guard: prefer `let exe = lib.getExe' pkgs.pkg "bin"; in "${exe} …" over direct ${pkgs.*}/bin paths
    # Lua (non-nvim; nvim is a vendored config)
    if command -v selene >/dev/null 2>&1; then selene files/gui files/mpv; else echo "selene not found — skipping Lua lint"; fi
    # Enable with: EXECSTART_GUARD=1 just lint
    if [ "${EXECSTART_GUARD:-}" = "1" ]; then \
      if grep -R -nE --include='*.nix' 'ExecStart\s*=\s*".*\$\{pkgs\.[^}]+\}/bin/' modules | grep -q .; then \
        echo 'Found ExecStart using direct ${pkgs.*}/bin path. Prefer:' >&2; \
        echo '  let exe = lib.getExe'"'"' pkgs.<pkg> "<bin>"; in "${exe} …"' >&2; \
        grep -R -nE --include='*.nix' 'ExecStart\s*=\s*".*\$\{pkgs\.[^}]+\}/bin/' modules || true; \
        exit 1; \
      fi; \
    fi
    # Optional guard: if using the "let exe … in \"${exe} …\"" pattern, prefer lib.escapeShellArgs for args
    # Enable with: ESCAPEARGS_GUARD=1 just lint
    if [ "${ESCAPEARGS_GUARD:-}" = "1" ]; then \
      tmp=$(mktemp); \
      grep -R -nE --include='*.nix' 'ExecStart\s*=\s*let[^;]+in\s*"\$\{exe\}\s' modules \
        | grep -v 'escapeShellArgs' \
        > "$tmp" || true; \
      if [ -s "$tmp" ]; then \
        echo 'Found ExecStart pattern using ${exe} without lib.escapeShellArgs for args:' >&2; \
        cat "$tmp" >&2; \
        rm -f "$tmp"; \
        exit 1; \
      fi; \
      rm -f "$tmp"; \
    fi
    # Shellcheck opt-in: check only files that declare a POSIX/Bash shebang
    # `:!files/x11/**` keeps the vendored FVWM rice out of the corpus (upstream
    # shell does not survive shfmt/shellcheck; see files/x11/README.md).
    git ls-files -z -- '*.sh' '*.bash' ':!files/x11/**' 2>/dev/null \
      | xargs -0 -r grep -lZ -m1 -E '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh' \
      | xargs -0 -r shellcheck -S warning -x
    bash "{{repo_root}}/scripts/dev/check-qml-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-qml-lint.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-hyprland-vars.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-markdown-language.sh" && \
    bash "{{repo_root}}/scripts/dev/check-all-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-osh-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-lusty-smoke.sh"
    just lint-annotations

# Check that all packages in environment.systemPackages have inline annotations
lint-annotations:
    bash "{{repo_root}}/scripts/dev/check-package-annotations.sh" "{{repo_root}}"

# Format Rust sources (edition-aware, via nearest Cargo.toml)
rustfmt:
    bash "{{repo_root}}/scripts/dev/check-rustfmt.sh" "{{repo_root}}" fix

docs-modules:
    # Generate modules documentation (opt-in)
    nix build .#docs-modules -o .result-docs --option substitute false
    mkdir -p docs/howto
    cp -f .result-docs/modules.md docs/howto/modules.md
    rm -f .result-docs
    chmod +w docs/howto/modules.md
    echo "Generated docs/howto/modules.md"

# Regenerate the codebase map (docs/codebase.md) for agents/quick orientation
codebase:
    "{{repo_root}}/packages/local-bin/bin/gen-codebase" "{{repo_root}}"; \
    nix fmt # normalize markdown (mdformat) so the artifact is fmt-stable

# Fail if the committed generated docs drift from what the generators produce.
# They are checked-in artifacts (docs/codebase.md, docs/howto/modules.md), so a
# structure/flag change that forgets to regenerate them is a silent lie; run
# this before committing such a change (and after every audit, see
# docs/runbook-audit.md).
docs-guard:
    #!/usr/bin/env bash
    set -euo pipefail
    cd "{{repo_root}}"
    just codebase
    just docs-modules
    just fmt
    # -I: gen-codebase stamps the document with the generation time, so a
    # timestamp-only change must not count as drift (real content changes still
    # produce other lines in the hunk and fail the check).
    if ! git diff --quiet -I 'Generated: [0-9]' -- docs/codebase.md docs/howto/modules.md; then
      echo "Generated docs are stale — regenerate and commit them:" >&2
      git diff --stat -I 'Generated: [0-9]' -- docs/codebase.md docs/howto/modules.md >&2
      exit 1
    fi
    echo "generated docs are fresh"

# Update the flake lock (all inputs)
update:
    nix flake update

# Eval one odin feature flag: just flag features.dev.ai.omp.enable
flag flag-path="features.cli.broot.enable":
    nix eval .#nixosConfigurations.odin.config.{{ flag-path }} --option substitute false

# Regenerate hosts/odin/unbound-hosts.nix from its sources
# (unbound-local.txt + files/sources/malw-hosts.txt)
unbound-hosts:
    "{{repo_root}}/packages/local-bin/scripts/gen-unbound-hosts" "{{repo_root}}"; \
    nix fmt

# Freshness gate for the same generated file: reruns the generator against a
# scratch root (only the two sources are copied in) and diffs the result, so a
# stale committed file fails here instead of silently keeping old host entries.
# Not wired into the lint pass or the pre-commit hook — like docs-guard it runs
# a generator, which is slower than lint. Run it (and docs-guard) before
# committing changes to either source file.
unbound-hosts-guard:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/hosts/odin" "$tmp/files/sources"
    cp "{{repo_root}}/hosts/odin/unbound-local.txt" "$tmp/hosts/odin/"
    cp "{{repo_root}}/files/sources/malw-hosts.txt" "$tmp/files/sources/"
    "{{repo_root}}/packages/local-bin/scripts/gen-unbound-hosts" "$tmp"
    if ! diff -q "{{repo_root}}/hosts/odin/unbound-hosts.nix" "$tmp/hosts/odin/unbound-hosts.nix" >/dev/null; then
      echo "hosts/odin/unbound-hosts.nix is stale — run 'just unbound-hosts' and commit it:" >&2
      diff -u "{{repo_root}}/hosts/odin/unbound-hosts.nix" "$tmp/hosts/odin/unbound-hosts.nix" | head -40 >&2
      exit 1
    fi
    echo "unbound-hosts.nix is fresh"

hooks-enable:
    git config core.hooksPath .githooks

systemd-status:
    set -eu
    echo "== systemd --user failed units =="
    systemctl --user --failed || true
    echo
    echo "== recent user journal =="
    journalctl --user -b -n 120 --no-pager || true

clean-caches:
    set -eu
    repo=$(git rev-parse --show-toplevel)
    find "$repo" -type f -name '*.zwc' -delete || true
    find "$repo" -type d -name '__pycache__' -prune -exec rm -rf {} + || true
    find "$repo" -type f -name '*.pyc' -delete || true
    : "${XDG_CACHE_HOME:=$HOME/.cache}"
    : "${XDG_STATE_HOME:=$HOME/.local/state}"
    rm -rf "$XDG_CACHE_HOME/zsh" || true

# --- Package flake sync (git-subtree) -------------------------------------------------
# Push packages/ subtree to standalone nixos-pkgs repo
subtree-push-packages:
    cd "{{repo_root}}"; \
    if ! git remote | grep -q neg-pkgs; then \
      echo "Adding remote: git remote add neg-pkgs git@github.com:neg-serg/nixos-pkgs.git"; \
      git remote add neg-pkgs git@github.com:neg-serg/nixos-pkgs.git; \
    fi; \
    git subtree push --prefix=packages/ neg-pkgs main

# Pull updates from standalone nixos-pkgs repo back into packages/ subtree
subtree-pull-packages:
    cd "{{repo_root}}"; \
    if ! git remote | grep -q neg-pkgs; then \
      echo "Error: remote 'neg-pkgs' not configured. Run: git remote add neg-pkgs git@github.com:neg-serg/nixos-pkgs.git"; \
      exit 1; \
    fi; \
    git subtree pull --prefix=packages/ neg-pkgs main

# --- Profiling / Benchmarking -------------------------------------------------

# Generate perf+Inferno flamegraph SVG for nix eval
flamegraph-eval host="odin":
    bash scripts/dev/nix-flamegraph.sh {{ host }}

# Generate perf+Inferno flamegraph SVG for nix eval
profile-eval: flamegraph-eval

# --- TidalCycles Live Coding --------------------------------------------------
# Engine, editor, recording and monitoring are handled by the `tidalctl` CLI
# (packages/tidalctl); recipes below are thin wrappers over it plus the Renoise
# launcher, so a daily live-coding session is `just tidal-start` + `just renoise`.

# Start the SuperDirt engine (sclang + scsynth) in the background
tidal-start:
    @tidalctl start

# Stop the engine
tidal-stop:
    @tidalctl stop

# Restart the engine (applies edits to superdirt_startup.scd / synths.scd)
tidal-restart:
    @tidalctl restart

# Engine status: processes, OSC ports, audio links
tidal-status:
    @tidalctl status

# Start the engine and open the demo jam scene in nvim
tidal-demo:
    @tidalctl demo

# Open the Tidal workspace in nvim with a visible ghci terminal (right split)
tidal-edit:
    @$HOME/.local/bin/tidal-edit

# Create a new .tidal file and open it
tidal-new:
    @tidalctl new

# Record SuperDirt output (prompts for duration)
tidal-record:
    @tidalctl record

# Live PipeWire monitor (pw-top)
tidal-monitor:
    @tidalctl monitor

# Open the ZestBay patchbay (distrobox Arch container)
tidal-patch:
    @tidalctl patch

# Run the Renoise tracker under pw-jack (JACK driver into the shared graph)
renoise:
    @$HOME/.local/bin/renoise-pwj

# Send OSC to Renoise's built-in OSC server (help lists all commands)
renoise-osc args="":
    @renoise-osc {{ args }}

# Record the Renoise audio (game-stereo sink by default; see renoise-osc help record)
renoise-record args="":
    @renoise-record {{ args }}
