# Repository development helpers for NixOS workflows
set shell := ["bash", "-cu"]

# Repository root for the repo-wide recipes. Every recipe run evaluates this
# backtick, so it falls back to the invocation dir when not in a git repo.
repo_root := `git rev-parse --show-toplevel 2>/dev/null || pwd`
# Shared invocation of scripts/dev/nix-seed-fods.sh: called directly from the
# deploy recipes rather than through `just seed`, because a nested `just` needs a
# writable runtime dir and dies in a sandboxed runner.
seed_fods := "bash " + repo_root + "/scripts/dev/nix-seed-fods.sh"

# --- System Management -----------------------------------------------------------

# Seed missing fixed-output sources (tarballs, patches) through the SOCKS5 proxy.
# Builds are sandboxed into a private network namespace, so a proxy on 127.0.0.1
# is unreachable from inside a fetch, and nixpkgs' `impureEnvVars` (http_proxy,
# all_proxy, ...) are filled from the nix-daemon's environment, not the
# caller's. This downloads the sources client-side instead: the expected
# fixed-output store paths appear, and the real build needs no network at all.
# Needed because cache.nixos.org, download.qt.io and friends are blocked here.
# Usage: just seed [host]
seed host="trantor":
    {{seed_fods}} \
      ".#nixosConfigurations.{{ host }}.config.system.build.toplevel" \
      --option substitute false

# Rebuild and switch to the new system configuration
# Usage: just deploy [host]
deploy host="trantor": check-eval hooks-ensure
    # Build system closure with network tuning
    nix build .#nixosConfigurations.{{ host }}.config.system.build.toplevel \
      --out-link result \
      --option connect-timeout 60 \
      --option download-attempts 2 \
      --option stalled-download-timeout 600

    # Update system profile
    sudo nix-env -p /nix/var/nix/profiles/system --set $(readlink -f result)
    # Switch to new configuration
    sudo ./result/bin/switch-to-configuration switch

# Deploy (Legacy/Slow) - keeps nh features like pretty print
deploy-nh host="trantor": check-eval hooks-ensure
    nh os switch . --hostname {{ host }}

# Deploy with maximum verbosity (logs + trace + verbose)
deploy-debug host="trantor": check-eval hooks-ensure
    nh os switch . --hostname {{ host }} -L -t -v

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
switch-sudo host="trantor": check-eval hooks-ensure
    sudo nixos-rebuild switch --flake .#{{ host }} < /dev/null

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
agent-switch toplevel: check-eval hooks-ensure
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

# Report what the pending configuration is *before* any build or switch:
# channel version, code name, revision and kernel come from a single pure
# evaluation, and the package-level delta comes from the derivation closures of
# the pending toplevel and of the running system (`nix-store -qR` over .drv
# files) — nothing here compiles. Once `result` holds a build, its realized
# closure is diffed against the running system for exact old→new versions, the
# only part that needs the artifact.
# Usage: just pending [host]
pending host="trantor":
    bash "{{repo_root}}/scripts/dev/pending-version.sh" "{{repo_root}}" "{{ host }}"

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

# Same check set as `just check`, but as a parallel queue: nix-eval-jobs
# evaluates every `checks.<system>.*` attr concurrently, nix-build builds only
# what no substituter has yet (`--skip-cached`). Substitution stays ON here —
# the point is throughput, not a from-source determinism proof; use `just check`
# when the question is "does it build from scratch".
# `--eval-workers 2`: one NixOS eval peaks ~3.6GiB (see `preflight` above).
check-fast:
    nix-fast-build --flake .#checks --skip-cached --eval-workers 2 --no-link

# Cheap eval gate before a deploy: catches a broken flake before root builds
# or activates anything. It does not build the check scripts; use `just check`
# for the full gate.
check-eval:
    nix flake check --no-build

# Print the counts advertised by README's "Project Statistics" table.
stats:
    bash "{{repo_root}}/scripts/dev/repo-stats.sh" "{{repo_root}}"

# Fail when the README numbers no longer match the tree (also runs in `lint`).
stats-check:
    bash "{{repo_root}}/scripts/dev/repo-stats.sh" --check "{{repo_root}}"

# Commit the pending tree with a message written by the local model
# (`llmctl commit`): message and commit in one step, tracked changes only.
# `just commit --all` also stages new (untracked) files; `--dry-run` prints
# the message without committing. `just commit --split` asks the model for a
# few logical commits and makes them one by one (whole files, never hunks).
commit *args:
    python3 "{{repo_root}}/modules/llm/llmctl.py" commit --repo "{{repo_root}}" {{args}}

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
      black --check --line-length 79 --extend-exclude files/kitty .; \
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
    bash "{{repo_root}}/scripts/dev/check-plm.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-scene-events.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-plugin-sandbox.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-hyprland-vars.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-relative-paths.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-absolute-home.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-doc-links.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-markdown-language.sh" && \
    bash "{{repo_root}}/scripts/dev/repo-stats.sh" --check "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-all-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-osh-syntax.sh" "{{repo_root}}" && \
    bash "{{repo_root}}/scripts/dev/check-lusty-smoke.sh"
    just lint-annotations

# Compile-check every pleamar scene in the repo (`pleamar --check`). Skips when
# the binary is missing from PATH; also runs as part of `lint`.
pleamar-check:
    bash "{{repo_root}}/scripts/dev/check-plm.sh" "{{repo_root}}"

# A read-only check-up of the running shell: one process per scene (with its fds,
# threads and RSS), helpers that should appear once, Hyprland bindings registered
# twice, and pleamar's panics and core dumps since boot. Needs the live session;
# not part of `lint`.
health:
    bash "{{repo_root}}/scripts/dev/check-pleamar-health.sh" "{{repo_root}}"

# The live bar's geometry, read from `pleamar --say bar describe`: the 25 px
# strip band, the symmetric 4 px side insets, the 7 px gaps and the absence of
# overlaps. Widths are deliberately not asserted — they are content-sized now
# (audio route, weather reading, workspace name), so only the invariants are
# stable. A session gate, not part of `lint`: it skips with a notice when the
# bar is not running.
pleamar-geometry:
    bash "{{repo_root}}/scripts/dev/check-pleamar-geometry.sh"

# Restart every pleamar scene after a compositor restart or a scale change.
# Hyprland can configure the layer surfaces before scale 2 is applied: the
# first sheet is 3840×35 at scale 1, then 1920×35 at scale 2. Pleamar updates
# the `screen.width` fact, but the scene keeps the load-time 3840 layout, so
# the bar's right row lands off-panel. Reloading the scenes after the
# compositor has settled is the recovery (see
# .agent/notes/2026-11-08-pleamar-scale-race.md).
pleamar-restart:
    systemctl --user restart \
      pleamar-bar.service \
      pleamar-launcher.service \
      pleamar-notifications.service \
      pleamar-osd.service \
      pleamar-toast.service

# What the shell spent on CPU at login, and what it spends now. `pleamar-login-cpu.timer`
# records every scene's `systemctl show` counters a minute after the session target (they
# are cumulative from each unit's start, so that window is the login burst); this renders
# the record next to the live counters: CPU seconds, % of one core, RSS and peak, restarts,
# and the rate since the record. `--json` for a script, `--watch SECONDS` for a live window —
# the `@` keeps just's own command echo out of the stdout a pipe is reading.
# Needs the live session; not part of `lint`.
pleamar-cpu *ARGS:
    @bash "{{repo_root}}/scripts/dev/pleamar-login-cpu.sh" {{ARGS}}

# What each layer of this session calls a size: the panel's device px, the compositor's
# scale, the logical px a scene draws its lengths in, and the shape of the wallpaper it
# would be handed. Run it before writing a size into a scene, and when a log line's
# numbers look wrong (scripts/dev/screen-numbers.sh says why: one monitor has four of
# them, and a lock face is configured in logical px but paints device px).
screen-numbers:
    bash "{{repo_root}}/scripts/dev/screen-numbers.sh"

# The palette gate: every scene that paints with `accent`, `coal`, `slate`, `ink`
# or `ink.dim` must import theme.plm, or it is silently drawing the frozen
# palette. Its own recipe rather than a line inside `lint`: that recipe keeps the
# checks it had, and this one is opted into.
plm-theme:
    bash "{{repo_root}}/scripts/dev/check-plm-theme.sh" "{{repo_root}}"

# Every `emit` in a scene must reach something: a logic handler, a scene rule, a component's event
# parameter, or a plugin's own logic. The class of bug it guards is the one the port was reported
# for — a capsule that compiles, presses, and does nothing. Pure python and no scene binary, so it
# runs inside `lint` as well.
scene-events:
    bash "{{repo_root}}/scripts/dev/check-scene-events.sh" "{{repo_root}}"

# The theme pipeline's own suite: the crate's hermetic cargo tests (fixtures, extractor
# goldens, CLI/error paths) run in the Nix build's checkPhase.
theme-test:
    nix build --no-link ".#pleamar-theme"

# The hostile-plugin gate: an unapproved plugin must be refused (and touch
# nothing), the same plugin must run once approved. Runs in `lint` too.
plugin-sandbox:
    bash "{{repo_root}}/scripts/dev/check-plugin-sandbox.sh" "{{repo_root}}"

# Render every plugin's proof scene, one PNG each, into a temp dir
# (`just render-plugins DIR` to keep them). Uses pleamar-wm headless when it is
# on PATH, otherwise the live session (`grim` + Hyprland); the pleamar binary
# itself comes from PATH or from the flake. Needs a graphics adapter: without one
# every scene is skipped with the reason, which is what happens in a sandbox.
render-plugins out="":
    bash "{{repo_root}}/scripts/dev/check-plugin-render.sh" "{{repo_root}}" {{if out != "" { "--out " + out } else { "" }}}

# Run a copy of the shell in a headless pleamar-wm (`pleamar-rig`, in
# packages/pleamar-harness): the tree is copied into $RIG with its own HOME and
# data, and `just rig sync|say|log|stop` work on that copy. Examples:
#   just rig start --scene bar --png /tmp/rig.png --at 3
#   just rig say bar describe
#   just rig stop
rig *ARGS:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{repo_root}}"
    wm=$(nix build --no-link --print-out-paths "$root#pleamar-wm")
    harness=$(nix build --no-link --print-out-paths "$root#pleamar-harness")
    exec env PLEAMAR_WM_BIN="$wm/bin/pleamar-wm" "$harness/bin/pleamar-rig" {{ARGS}}

# Resolve repo paths by name (see lib/README.md → Which resolver, where):
#   just paths keys files        what to write in Nix for files/…
#   just paths keys modules --any
#   just paths refs systemd-user who references it
#   just paths find wl-monitor   fuzzy-pick a file and list its references
#   just paths resolve ../../../lib/x.nix --from hosts/trantor/services/y.nix
paths *ARGS:
    "{{repo_root}}/packages/local-bin/bin/paths" --root "{{repo_root}}" {{ARGS}}

# Offline self-checks for the music tooling. Index/similar are Rust binaries
# (stub embedder, no torch/model/venv); the describe payload is still Python and
# needs a numpy-capable interpreter. Called from `lint`.
music-selftest:
    #!/usr/bin/env bash
    # The index/similar self-checks are the Rust `music-index`/`music-similar`
    # binaries now (stub embedder: no torch, no model, no venv). They are built
    # from the flake so this works without the tools on PATH; a machine that
    # cannot build them prints a skip.
    set -euo pipefail
    if out="$(nix build --no-link --print-out-paths ".#music-index-tools" 2>/dev/null)"; then
      "$out/bin/music-index" --selftest
      "$out/bin/music-similar" --selftest
    else
      echo "music index/similar selftest skipped (nix build .#music-index-tools failed)"
    fi
    # music-describe still runs torch; prefer an interpreter that can import numpy.
    venv_sp=/zero/ai/music-ai/venv-analysis/lib/python3.12/site-packages
    for py in "${MUSIC_AI_SELFTEST_PY:-}" "$HOME/.local/bin/python3.12" python3; do
      [ -n "$py" ] || continue
      command -v "$py" >/dev/null 2>&1 || continue
      if PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" -c 'import numpy' >/dev/null 2>&1; then
        PYTHONPATH="$venv_sp:${PYTHONPATH:-}" "$py" "{{repo_root}}/packages/local-bin/lib/music_describe.py" --selftest
        exit 0
      fi
    done
    echo "music-describe selftest skipped (no numpy-capable interpreter found)"

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

# Bump only the inputs that point at neg's own repositories (raise, wl, lusty,
# neg-pkgs, hyprscratch, rsmetrx, nix-cache-pin), keep each bump only when the
# toplevel still evaluates, and commit flake.lock without pushing. Heavy inputs
# (aurora-src, iosevka-neg) are opt-in; rollout-watch deploys the commit on its
# next tick. The trantor timer (features.system.flakeBump) runs this script
# weekly with --allow-skip.
# Usage: just bump-own [--all] [--no-commit] [--allow-skip]
bump-own *ARGS:
    bash "{{repo_root}}/scripts/dev/flake-bump-own.sh" {{ARGS}}

# Search a nix-cache-pin pin for binary-cache hits without touching the tree.
# The CLI edits ./flake.nix of the flake it runs in, so run this from the repo
# root. Pins live in flake/cache-pin.nix; pass extra CLI flags (--plan,
# --check-current, ...) by calling `nix run .#cache-pin-<pin> -- <flags>`.
# Usage: just cache-pin [pin]
cache-pin pin="cachyos":
    nix run ".#cache-pin-{{ pin }}" -- --dry-run

# Apply a nix-cache-pin pin: rewrite the input revision in flake.nix and re-lock
# it. Verify the result (diff, `just check`) before rebuilding anything.
# Usage: just cache-pin-apply [pin]
cache-pin-apply pin="cachyos":
    nix run ".#cache-pin-{{ pin }}"

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

# Create/fill the MOSS-Music-8B venv (the model's custom transformers 4.57.1
# code on CPU torch) and fetch its Instruct bf16 weights (18.1 GiB). There is no
# ggml port for it, so the moss-music wrapper runs the reference PyTorch code.
music-moss-setup *ARGS:
    bash "{{repo_root}}/scripts/dev/moss-music-setup.sh" {{ARGS}}

music-moss-venv *ARGS:
    bash "{{repo_root}}/scripts/dev/moss-music-setup.sh" --only venv {{ARGS}}

# --set thinking|both also fetches the chain-of-thought variant (18.1 GiB each).
music-moss-models *ARGS:
    bash "{{repo_root}}/scripts/dev/moss-music-setup.sh" --only models {{ARGS}}

# Install chordotomy (beat-aligned chords, key changes, Roman numerals from a
# recording) as a uv tool plus its Beat This! weights; --check/--dry-run are
# read-only. It lives in ~/.local, so no rebuild is needed to use it.
music-chordotomy-setup *ARGS:
    bash "{{repo_root}}/scripts/dev/chordotomy-setup.sh" {{ARGS}}

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
    music-apply-tags {{ARGS}}

# Eval one trantor feature flag: just flag features.cli.broot.enable
flag flag-path="features.cli.broot.enable":
    nix eval .#nixosConfigurations.trantor.config.{{ flag-path }} --option substitute false

# Memoized `nix eval` in two tiers, keyed on a content hash of the files the
# evaluation reads. Nix's own eval cache cannot help here: a dirty worktree
# changes its fingerprint on every call, so it never hits.
#   just eval-gate        tier A — `config.system.nixos.label`, ~1.3 s cold, ~70 ms
#                         on a hit. The "it still evaluates" signal: the module
#                         tree without instantiating pkgs. Call it after every edit.
#                         Key: the EVALUATION INPUT SET — every *.nix, flake.lock and
#                         the non-Nix files a .nix file names literally (udev rules,
#                         herdr config, sops paths, …), discovered per run. Editing
#                         a doc, a QML or a .plm scene is a HIT; editing any *.nix is
#                         a miss.
#   just eval-gate --drv  tier B — the toplevel drvPath: ~3.7 s cold (down from
#                         ~9.0 s: the evaluation fans out over systemPackages
#                         through Determinate's `builtins.parallel` at
#                         eval-cores 16, and falls back to the plain command when
#                         that primop is missing), ~29 ms on a hit of a clean
#                         tree, ~76 ms on one with ~1700 changed paths. What a
#                         rollout needs. Key: the WHOLE tree, because the toplevel
#                         embeds the flake source — preserve-flake pins
#                         self.outPath — so any content change moves the drvPath.
#                         It is built from git's own content addresses (HEAD,
#                         `ls-files -s` blob OIDs, one batched `hash-object` for
#                         every path status calls dirty or untracked) instead of a
#                         whole-tree diff plus a sha256 per file: same
#                         invalidation strength, 6x cheaper on a dirty tree.
#                         `--json` returns {label, drvPath, toplevel, name, system}
#                         from that one evaluation; `--field NAME` picks one, and
#                         `--print-key` prints the key a state hashes to.
# A hit is the stored output of a live eval of exactly that state, never a guess;
# scripts/dev/nixos-eval-gate.test.sh proves it against `nix eval` per state.
# Anything unhashable (unreadable input, unknown file type, unwritable cache dir)
# falls through to a real eval with a notice. Entries live in
# $XDG_CACHE_HOME/nixos-eval-gate/<key>, or in the repo-local .agent/tmp-nix-cache
# when $HOME is not writable (the same fallback `just update` has).
# `--no-cache` forces a real eval, `--verbose` shows tier, key, hit/miss and the
# proof record each answer was stored with.
# Two memoized eval tiers: label (fast) and toplevel drvPath (--drv)
eval-gate *ARGS:
    bash "{{repo_root}}/scripts/dev/nixos-eval-gate.sh" {{ARGS}}

# Regenerate hosts/trantor/unbound-hosts.nix from its sources
# (unbound-local.txt + files/sources/malw-hosts.txt, minus malw-hosts-allow.txt)
unbound-hosts:
    nix run .#gen-unbound-hosts -- "{{repo_root}}"; \
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
    nix run .#gen-unbound-hosts -- "$tmp"
    if ! diff -q "{{repo_root}}/hosts/trantor/unbound-hosts.nix" "$tmp/hosts/trantor/unbound-hosts.nix" >/dev/null; then
      echo "hosts/trantor/unbound-hosts.nix is stale — run 'just unbound-hosts' and commit it:" >&2
      diff -u "{{repo_root}}/hosts/trantor/unbound-hosts.nix" "$tmp/hosts/trantor/unbound-hosts.nix" | head -40 >&2
      exit 1
    fi
    echo "unbound-hosts.nix is fresh"

hooks-enable:
    git config core.hooksPath .githooks

# Enable the repo hooks when this clone has no core.hooksPath yet. Deploy
# targets and the devshell shellHook call this, so a fresh clone cannot commit
# without the lint/commit-msg gate.
hooks-ensure:
    #!/usr/bin/env bash
    set -euo pipefail
    root="{{repo_root}}"
    if [ -z "$(git -C "$root" config --get core.hooksPath 2>/dev/null)" ]; then
      git -C "$root" config core.hooksPath .githooks
      echo "git hooks enabled (core.hooksPath=.githooks)"
    fi

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

# just runs each recipe line in its own shell, so this must be one script: the
# old per-line form lost `repo` between lines and died on `set -u` (it never
# deleted anything). The uv/ruff caches are ad-hoc run leftovers in the root.
clean-caches:
    #!/usr/bin/env bash
    set -euo pipefail
    repo=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
    find "$repo" -type f -name '*.zwc' -delete || true
    find "$repo" -type d -name '__pycache__' -prune -exec rm -rf {} + || true
    find "$repo" -type f -name '*.pyc' -delete || true
    rm -rf "$repo/.uv-cache" "$repo/.ruff_cache" || true
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

# Eval-time regression guard: median of N plain drvPath evals vs the committed
# baseline; fails above +15%. Run before/after closure-minimization or
# dendritic/import-tree experiments.
# Usage: just bench-eval [runs]
bench-eval runs="5":
    bash "{{repo_root}}/scripts/dev/eval-bench.sh" --runs {{ runs }}

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

# --- On-demand apps ---------------------------------------------------------------

# List the on-demand GC roots and the store paths they pin
apps:
    @nix-apps list

# Compare every root with the current flake (current/stale/external)
apps-status:
    @nix-apps status

# Rebuild roots from the current flake (all managed, or the names given)
apps-update *names:
    @nix-apps update {{ names }}

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

# Local GUI agent loop (plan -> act -> verify) driving one window through
# computer-use-linux; planner, actor and verifier are llama-swap models, so
# nothing leaves the host. Artifacts land in /tmp/webstep-<stamp>/.
# Example: just webstep run --goal "add album Rumours to Alex" --app-id vivaldi-stable
webstep *ARGS:
    "{{repo_root}}/scripts/dev/webstep" {{ARGS}}

# --- Steam 32-bit graphics --------------------------------------------------------

# Build and pin the out-of-closure 32-bit Mesa that Steam launch options use for
# 32-bit games (the system ships no 32-bit graphics drivers on purpose; see
# modules/user/games/launchers.nix). Writes the GC root at
# ~/.local/state/rct32-mesa — re-run only after the root is gone or to refresh
# drivers on a nixpkgs bump.
rct32-mesa:
    nix build nixpkgs#pkgsi686Linux.mesa --out-link ~/.local/state/rct32-mesa

# Reproducible RCT Classic setup: 32-bit Mesa GC root + Steam launch options.
# Steam must be closed; see scripts/dev/steam-rct32.sh.
rct32-setup:
    bash "{{repo_root}}/scripts/dev/steam-rct32.sh"
