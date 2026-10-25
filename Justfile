# Repository development helpers for NixOS workflows
set shell := ["bash", "-cu"]

# Repository root for the repo-wide recipes. Every recipe run evaluates this
# backtick, so it falls back to the invocation dir when not in a git repo.
repo_root := `git rev-parse --show-toplevel 2>/dev/null || pwd`

# --- System Management -----------------------------------------------------------

# Rebuild and switch to the new system configuration
# Usage: just deploy [host]
deploy host="trantor":
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
deploy-nh host="trantor":
    nh os switch . --hostname {{ host }} --option substitute false

# Deploy with maximum verbosity (logs + trace + verbose)
deploy-debug host="trantor":
    nh os switch . --hostname {{ host }} -L -t -v --option substitute false

# Alias for deploy
switch host="trantor":
    just deploy {{ host }}

# Plain root switch: `nixos-rebuild` itself, no nh and no nom in the path.
# This is the fallback when the agent rollout is off, when the change *is* the
# mechanism, and the way out when nix-output-monitor cannot read the log of the
# Nix it now runs with (nom 2.2.0 dies on activity type 10113, CopySourcePath,
# emitted by Determinate Nix 3.23.3).
# The stdin redirect is not decoration: when the caller's stdin is a socket
# (systemd-run --pipe, some agent runners) nixos-rebuild refuses it, builds the
# whole system and applies nothing. `--option substitute false` because
# cache.nixos.org is unreliable from this host.
# Usage: just switch-sudo [host]
switch-sudo host="trantor":
    sudo nixos-rebuild switch --flake .#{{ host }} --option substitute false < /dev/null

# Cache-status preflight for a rebuild: per host, how much of the *whole closure*
# still has to be built from source and how much can be substituted. Matters here
# because the rollout runs with `--option substitute false`, so a flake bump that
# drops a host out of cache means hours of compiling.
# nix-eval-jobs walks the closure (neededBuilds/neededSubstitutes), ~20s per host;
# 2 workers because one NixOS eval peaks at ~3.6GiB.
# The substituter override is not optional: install.determinate.systems (in the
# default list) stalls 120s per narinfo, one lookup per store path, which turns
# this into a multi-hour hang.
# Usage: just preflight [host]
preflight host="":
    nix-eval-jobs --check-cache-status \
      --option substituters "https://cache.nixos.org/" \
      --option connect-timeout 15 \
      --workers 2 \
      --select 'cfgs: builtins.mapAttrs (_: c: c.config.system.build.toplevel) cfgs' \
      --flake .#nixosConfigurations \
    | jq -r --arg host "{{ host }}" 'select($host == "" or .attr == $host) | "\(.attr)\t\(.cacheStatus)\tbuild=\(.neededBuilds | length)\tsubst=\(.neededSubstitutes | length)"'

# Agent rollout: activate the /etc/nixos flake without a password. The argument is
# the toplevel the agent already built and verified — the root-owned unit refuses to
# switch when the tree now builds something else (modules/security/agent-switch.nix).
# Usage: just agent-switch /nix/store/…-nixos-system-trantor-…
agent-switch toplevel:
    #!/usr/bin/env bash
    set -uo pipefail
    rc=0
    mkdir -p /etc/nixos/.agent
    printf '%s\n' "{{toplevel}}" > /etc/nixos/.agent/switch-request
    # polkit allows the main user to start exactly this unit, so no sudo here:
    # setuid sudo cannot run inside a session sandbox (no_new_privs).
    # nixos-agent-rollout is the constant unit file; the legacy name only exists
    # until the bootstrap block in modules/security/agent-switch.nix is dropped
    # (it is still the unit the *running* generation knows about).
    if systemctl cat nixos-agent-rollout.service > /dev/null 2>&1; then
      unit=nixos-agent-rollout.service
    else
      unit=nixos-agent-switch.service
    fi
    systemctl start "$unit" || rc=$?
    # The unit only launches the rollout (a Type=oneshot kept running would
    # deadlock the activation that starts it); the work is in the transient
    # nixos-agent-rollout-work unit, so wait for that one to finish.
    for _ in $(seq 1 900); do
      systemctl is-active --quiet nixos-agent-rollout-work.service || break
      sleep 1
    done
    systemctl show -p ActiveState -p ExecMainStatus "$unit"
    journalctl -u nixos-agent-rollout-work -n 40 --no-pager | tail -n 40
    exit "$rc"

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
    # Guard: repo-wide Nix anti-patterns (with-pkgs forms, ExecStart file/dir
    # mutations, bare `with lib`). Rule list and env gates:
    #   bash scripts/dev/lint-guards.sh --list
    bash "{{repo_root}}/scripts/dev/lint-guards.sh" "{{repo_root}}"
    # `&&` so a failing ruff fails this line: the recipe runs under `bash -cu`
    # (no -e) and a plain `;` would let black's success mask it.
    if git ls-files -- '*.py' >/dev/null 2>&1; then \
      ruff check -- . && \
      black --check --line-length 79 --extend-exclude '(files/kitty|files/art/fun-art|files/qs-wallpaperpicker)' .; \
    fi
    # TOML syntax/style — tracked files only: a bare `taplo lint` follows result/
    # into the nix store (pyright's typeshed alone is ~200 METADATA.toml) plus the
    # local nix/ dump, for ~1s of pointless walking; RUST_LOG=warn hides taplo's
    # file-list INFO line.
    if command -v taplo >/dev/null 2>&1; then git ls-files -z -- '*.toml' 2>/dev/null | RUST_LOG=warn xargs -0 -r taplo lint; else echo "taplo not found — skipping TOML lint"; fi
    # Rust formatting (edition-aware via nearest Cargo.toml)
    if command -v rustfmt >/dev/null 2>&1; then bash scripts/dev/check-rustfmt.sh; else echo "rustfmt not found — skipping Rust check"; fi
    # Lua (non-nvim; nvim is a vendored config)
    if command -v selene >/dev/null 2>&1; then selene files/gui files/mpv; else echo "selene not found — skipping Lua lint"; fi
    # Music index/similar payloads: offline stub-embedder selftests (no
    # torch/model/venv), skipped with a notice when python3 is missing —
    # same style as rustfmt/selene above.
    if command -v python3 >/dev/null 2>&1; then just music-selftest; else echo "python3 not found — skipping music payload selftest"; fi
    # Shellcheck opt-in: check only files that declare a POSIX/Bash shebang
    git ls-files -z -- '*.sh' '*.bash' 2>/dev/null \
      | xargs -0 -r grep -lZ -m1 -E '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh' \
      | xargs -0 -r shellcheck -S warning -x
    bash "{{repo_root}}/scripts/dev/check-qml-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-qml-lint.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-plm.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-plugin-sandbox.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-hyprland-vars.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-relative-paths.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-markdown-language.sh" && \
    bash "{{repo_root}}/scripts/dev/check-all-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-osh-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-lusty-smoke.sh"
    just lint-annotations

# Compile-check every pleamar scene in the repo (`pleamar --check`). Skips when
# the binary is missing from PATH; also runs as part of `lint`.
pleamar-check:
    bash "{{repo_root}}/scripts/dev/check-plm.sh" "{{repo_root}}"

# The palette gate: every scene that paints with `accent`, `coal`, `slate`, `ink`
# or `ink.dim` must import theme.plm, or it is silently drawing the frozen
# palette. Its own recipe rather than a line inside `lint`: that recipe keeps the
# checks it had, and this one is opted into.
plm-theme:
    bash "{{repo_root}}/scripts/dev/check-plm-theme.sh" "{{repo_root}}"

# The theme pipeline's own suite: hermetic, runs theme.sh against image fixtures in a
# throwaway HOME and pins the extractor's goldens. A recipe of its own because nothing ran
# it and it rotted: seven of its checks were red on 2026-10-26, all of them stale
# expectations from before the shell's tones became the reference's own tokens.
theme-test:
    bash "{{repo_root}}/files/pleamar/scripts/theme/test.sh"

# The hostile-plugin gate: an unapproved plugin must be refused (and touch
# nothing), the same plugin must run once approved. Runs in `lint` too.
plugin-sandbox:
    bash "{{repo_root}}/scripts/dev/check-plugin-sandbox.sh" "{{repo_root}}"

# Measure the bar's widgets against the reference's, window by window: the drift
# of the ink profile (gated at 4 logical px) and the icon pairs of the right
# window (gated at 4 px of position and 3 of width). The left window's ink
# profile and run table are printed and not gated — that window carries the
# throughput digits and the weather, which differ between the bars by
# construction. `--shot FILE` measures an existing frame.
parity-clusters *ARGS:
    bash "{{repo_root}}/scripts/dev/parity-clusters.sh" "{{repo_root}}" {{ARGS}}

# Measure the pleamar bar against the live Quickshell bar, pixel by pixel:
# captures the bar strip before (quickshell) and while the pleamar scene is up,
# prints the mean difference and the share of visibly changed pixels, and writes
# qs | pleamar | diff into DIR.
#   just parity-bar                 measure the chrome only
#   just parity-bar DIR             keep the artifacts in DIR
#   just parity-bar DIR approve     also approve the plugins, so their data
#                                   (cover, analyser, flags, dB) is live
#   just parity-bar DIR approve hide  stop quickshell for the capture (its bar
#                                   would otherwise show through the port's
#                                   transparent parts) and start it again after
# (`just` owns its own flags, so `--approve` cannot be passed through the
# recipe; the word `approve` is the switch.)
parity-bar out="" approve="" hide="":
    bash "{{repo_root}}/scripts/dev/parity-bar.sh" "{{repo_root}}" {{if out != "" { "--out " + out } else { "" }}} {{if approve != "" { "--approve" } else { "" }}} {{if hide != "" { "--hide-qs" } else { "" }}}

# Render every plugin's proof scene, one PNG each, into a temp dir
# (`just render-plugins DIR` to keep them). Uses pleamar-wm headless when it is
# on PATH, otherwise the live session (`grim` + Hyprland); the pleamar binary
# itself comes from PATH or from the flake. Needs a graphics adapter: without one
# every scene is skipped with the reason, which is what happens in a sandbox.
render-plugins out="":
    bash "{{repo_root}}/scripts/dev/check-plugin-render.sh" "{{repo_root}}" {{if out != "" { "--out " + out } else { "" }}}

# Resolve repo paths by name (see lib/README.md → Which resolver, where):
#   just paths keys files        what to write in Nix for files/…
#   just paths keys modules --any
#   just paths refs systemd-user who references it
#   just paths find wl-monitor   fuzzy-pick a file and list its references
#   just paths resolve ../../../lib/x.nix --from hosts/trantor/services/y.nix
paths *ARGS:
    "{{repo_root}}/packages/local-bin/bin/paths" --root "{{repo_root}}" {{ARGS}}

# Offline self-checks for the music index/similar payloads, using a stub
# embedder (no torch, no model, no venv; a machine without numpy prints a
# skip and exits 0). Called from `lint`; see `just --list` for the recipe.
music-selftest:
    #!/usr/bin/env bash
    # Prefer an interpreter that can actually import numpy (the venv's cp312
    # builds do not load under the system 3.14), then fall back to whatever
    # python3 is around: the payloads print a skip and exit 0 without numpy.
    set -euo pipefail
    venv_sp=/zero/ai/music-ai/venv-analysis/lib/python3.12/site-packages
    for py in "${MUSIC_AI_SELFTEST_PY:-}" "$HOME/.local/bin/python3.12" python3; do
      [ -n "$py" ] || continue
      command -v "$py" >/dev/null 2>&1 || continue
      if PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" -c 'import numpy' >/dev/null 2>&1; then
        PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" "{{repo_root}}/packages/local-bin/lib/music_index.py" --selftest
        PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" "{{repo_root}}/packages/local-bin/lib/music_similar.py" --selftest
        PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" "{{repo_root}}/packages/local-bin/lib/music_describe.py" --selftest
        exit 0
      fi
    done
    echo "music payload selftest skipped (no numpy-capable interpreter found)"

# Check that all packages in environment.systemPackages have inline annotations
lint-annotations:
    bash "{{repo_root}}/scripts/dev/check-package-annotations.sh" "{{repo_root}}"

# Session-format regression gate for the dsh patches. Needs an installed dsh store path.
check-dsh-sessions dsh-path:
    bash "{{repo_root}}/scripts/dev/check-dsh-sessions.sh" {{dsh-path}}

# Format Rust sources (edition-aware, via nearest Cargo.toml)
rustfmt:
    bash "{{repo_root}}/scripts/dev/check-rustfmt.sh" "{{repo_root}}" fix

# Update the flake lock (all inputs). The agent session sandbox cannot write $HOME
# (Landlock reports it writable but denies the opens), so fall back to the repo-local
# nix cache the way .agent/tmp-nix-cache is already used by the build recipes.
update:
    cache="${XDG_CACHE_HOME:-$HOME/.cache}"; \
    if ( mkdir -p "$cache/nix" && touch "$cache/nix/.probe" ) 2>/dev/null; then \
      rm -f "$cache/nix/.probe"; \
    else \
      cache="{{repo_root}}/.agent/tmp-nix-cache"; \
      echo "update: using repo-local nix cache at $cache" >&2; \
    fi; \
    XDG_CACHE_HOME="$cache" nix flake update

# Re-point the music-AI venv interpreters after a nix-collect-garbage run (the
# venvs symlink to store pythons that have no GC root). --check for a read-only
# status report, --dry-run to preview the actions.
fix-music-venvs *ARGS:
    bash "{{repo_root}}/scripts/dev/fix-music-venvs.sh" {{ARGS}}

# Move the music-AI venv from the CUDA torch build to the local ROCm wheel so
# music-embed/music-tags can use the GPU (torchaudio/torchvision are swapped
# with it). --check / --dry-run are read-only; see docs/howto/local-music-ai.md.
music-ai-rocm *ARGS:
    bash "{{repo_root}}/scripts/dev/music-ai-rocm.sh" {{ARGS}}

# Create/fill the trained MTG tagger (venv-mtg with essentia-tensorflow) and
# fetch its EffNet/head models; --check/--dry-run are read-only. Feeds
# music-mtg-tags: Discogs-400 styles + Jamendo mood/theme/instrument.
# audio.cpp model files (Audio Flamingo Next GGUF, ~8.7 GiB).
audio-cpp-models *ARGS:
    bash "{{repo_root}}/scripts/dev/audio-cpp-models.sh" {{ARGS}}

music-mtg-setup *ARGS:
    bash "{{repo_root}}/scripts/dev/music-mtg-setup.sh" {{ARGS}}

# Refresh every derived music artefact in one incremental pass: MERT index ->
# MTG tags -> mood/genre playlists (the weekly timer runs the same script).
# --check / --dry-run are read-only; see docs/howto/local-music-ai.md.
music-refresh *ARGS:
    bash "{{repo_root}}/scripts/dev/music-refresh.sh" {{ARGS}}

# Read-only report on the whole music-AI stack: wrappers, index, tags,
# playlists, models, venvs, GPU and the refresh timer. Prints a to-do list and
# exits non-zero when something needs attention.
music-ai-status *ARGS:
    bash "{{repo_root}}/scripts/dev/music-ai-status.sh" {{ARGS}}

# Write the ML mood (and optionally the Discogs style) into the audio files so
# players and MPD search see them; dry run unless --apply is passed, and every
# change is logged to a JSONL file. See docs/howto/local-music-ai.md.
music-apply-tags *ARGS:
    python3 "{{repo_root}}/scripts/dev/music-apply-tags.py" {{ARGS}}

# Eval one trantor feature flag: just flag features.dev.ai.omp.enable
flag flag-path="features.cli.broot.enable":
    nix eval .#nixosConfigurations.trantor.config.{{ flag-path }} --option substitute false

# Regenerate hosts/trantor/unbound-hosts.nix from its sources
# (unbound-local.txt + files/sources/malw-hosts.txt, minus malw-hosts-allow.txt)
unbound-hosts:
    "{{repo_root}}/packages/local-bin/scripts/gen-unbound-hosts" "{{repo_root}}"; \
    nix fmt

# Freshness gate for the same generated file: reruns the generator against a
# scratch root (only the source files are copied in) and diffs the result, so a
# stale committed file fails here instead of silently keeping old host entries.
# Not wired into the lint pass or the pre-commit hook — it runs a generator, which is slower than
# lint. Run it before committing changes to either source file.
unbound-hosts-guard:
    #!/usr/bin/env bash
    set -euo pipefail
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/hosts/trantor" "$tmp/files/sources"
    cp "{{repo_root}}/hosts/trantor/unbound-local.txt" "$tmp/hosts/trantor/"
    cp "{{repo_root}}/files/sources/malw-hosts.txt" "$tmp/files/sources/"
    cp "{{repo_root}}/files/sources/malw-hosts-allow.txt" "$tmp/files/sources/"
    "{{repo_root}}/packages/local-bin/scripts/gen-unbound-hosts" "$tmp"
    if ! diff -q "{{repo_root}}/hosts/trantor/unbound-hosts.nix" "$tmp/hosts/trantor/unbound-hosts.nix" >/dev/null; then
      echo "hosts/trantor/unbound-hosts.nix is stale — run 'just unbound-hosts' and commit it:" >&2
      diff -u "{{repo_root}}/hosts/trantor/unbound-hosts.nix" "$tmp/hosts/trantor/unbound-hosts.nix" | head -40 >&2
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

# AppArmor: what is loaded, in which mode, and what this boot denied.
# Denials in "complain" mode are informational (the daemon was allowed);
# they are the list of rules to add before flipping a daemon to enforce.
# See modules/security/apparmor.nix.
apparmor-status:
    set -eu
    systemctl status apparmor.service --no-pager | head -12 || true
    aa-status || true

# AppArmor denials for this boot, optionally filtered by daemon name
# (`grep -i ""` matches everything — just forbids deeper indentation inside a
# recipe). Two shapes to catch: a real denial is apparmor="DENIED", while a
# complain-mode violation is audited as apparmor="ALLOWED" with a non-empty
# denied_mask — grepping only "DENIED" silently reports nothing in complain.
# The same event is logged twice (bare audit: record, then AVC), so sort -u.
apparmor-denials daemon="":
    set -eu
    { journalctl -b --no-pager -o cat --grep 'apparmor="DENIED"' || true; journalctl -b --no-pager -o cat --grep 'apparmor="ALLOWED"' | grep -E 'denied_mask="[^"]+"' || true; } | sed -E 's/^(audit: type=1400 audit\([^)]*\): |AVC )//' | sort -u | grep -i "{{daemon}}" || true

# AppArmor: boot a throwaway VM with all eight profiles in "enforce" and run
# every check — the place to try a rule without aiming it at this machine.
# --offline: the closure comes from the local store, and without it nix stops on
#   the binary caches' narinfo lookups (they answer with a TLS EOF from here) and
#   looks hung for minutes per path instead of failing.
# --no-link: never touch ./result, which is the host deployment link the switch
#   scripts read (`readlink -f result`).
# See modules/security/apparmor.nix.
apparmor-test:
    set -eu
    cd "{{repo_root}}" && nix build --impure --file tests/apparmor-enforce.nix -L --offline --no-link

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
flamegraph-eval host="trantor":
    bash scripts/dev/nix-flamegraph.sh {{ host }}

# Generate perf+Inferno flamegraph SVG for nix eval
profile-eval: flamegraph-eval

# Rollout benchmark: eval+instantiate+realize timings for `fix` and `nix` on a
# one-line change (the `system.nixos.label` trigger in hosts/trantor/default.nix)
# Usage: just bench-rollout [runs] [engines]
bench-rollout runs="3" engines="fix,nix":
    scripts/dev/rollout-bench.sh --runs {{ runs }} --engines {{ engines }}

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

# --- Keyboard (QMK) ---------------------------------------------------------------

# Build and flash the Wellum keymap onto both Ferris Sweep halves (RP2040)
wellum:
    bash "{{repo_root}}/scripts/dev/qmk-wellum.sh" flash

# Build the Wellum keymap for the Ferris Sweep without flashing
wellum-build:
    bash "{{repo_root}}/scripts/dev/qmk-wellum.sh" build

# Build and flash the Wellum keymap onto an AVR Pro Micro/Elite-C Sweep
wellum-avr:
    WELLUM_CONVERT= bash "{{repo_root}}/scripts/dev/qmk-wellum.sh" flash
