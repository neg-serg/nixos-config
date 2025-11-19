# Repository development helpers for both NixOS and Home Manager workflows

set shell := ["bash", "-cu"]

# --- System-level docs/utilities -------------------------------------------------

# Generate aggregated options docs into docs/*.md
gen-options:
    repo_root="$(git rev-parse --show-toplevel)"; \
    cd "$repo_root" && scripts/gen-options.sh

# Generate and commit options docs if there are changes
gen-options-commit:
    set -euo pipefail
    repo_root="$(git rev-parse --show-toplevel)"
    cd "$repo_root"
    just gen-options
    if git diff --quiet -- docs; then \
      echo "No changes in docs"; \
    else \
      git add docs; \
      git commit -m "[docs/options] Regenerate options docs"; \
    fi

# Detect V-Cache CPU set and print recommended kernel masks
cpu-masks:
    repo_root="$(git rev-parse --show-toplevel)"; \
    cd "$repo_root" && scripts/cpu-recommend-masks.sh

# --- Repo-wide workflows (original Home Manager justfile) ------------------------

fmt:
    repo_root="$(git rev-parse --show-toplevel)"; \
    cd "$repo_root" && nix fmt

check:
    nix flake check -L

lint:
    set -eu
    statix check -- .
    deadnix --fail .
    # Guard: discourage `with pkgs; [ ... ]` lists (prefer explicit pkgs.*)
    if grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'with[[:space:]]+pkgs;[[:space:]]*\[' . | grep -q .; then \
      echo 'Found discouraged pattern: use explicit pkgs.* items instead of `with pkgs; [...]`' >&2; \
      grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'with[[:space:]]+pkgs;[[:space:]]*\[' . || true; \
      exit 1; \
    fi; \
    if grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'targetPkgs[[:space:]]*=[[:space:]]*pkgs:[[:space:]]*with[[:space:]]+pkgs' . | grep -q .; then \
      echo 'Found discouraged pattern in FHS targetPkgs: avoid `with pkgs`' >&2; \
      grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' 'targetPkgs[[:space:]]*=[[:space:]]*pkgs:[[:space:]]*with[[:space:]]+pkgs' . || true; \
      exit 1; \
    fi
    # Guard: avoid mkdir/touch/rm in ExecStartPre/ExecStart within systemd units
    # Prefer mkLocalBin or per-file force on managed files/wrappers.
    if grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
         'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules | \
       grep -v 'modules/dev/cachix/default.nix' | grep -q .; then \
      echo 'Found ExecStartPre/ExecStart with mkdir/touch/rm. Use mkLocalBin or per-file force instead.' >&2; \
      grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
        'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules \
        | grep -v 'modules/dev/cachix/default.nix' || true; \
      exit 1; \
    fi
    # Guard: avoid `with pkgs.lib` — use explicit pkgs.lib.*
    if grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.lib\b' . | grep -q .; then \
      echo "Found discouraged pattern: avoid 'with pkgs.lib'; use explicit pkgs.lib.*" >&2; \
      grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.lib\b' . || true; \
      exit 1; \
    fi
    # Guard: avoid generic `with pkgs.<ns>` — prefer explicit pkgs.<ns>.<item>
    if grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.[A-Za-z0-9_-]+' . | grep -v -E 'pkgs\.lib\b' | grep -q .; then \
      echo "Found discouraged pattern: avoid 'with pkgs.<ns>'; reference explicit pkgs.<ns>.<item>" >&2; \
      grep -R -nE --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' '\bwith[[:space:]]+pkgs\.[A-Za-z0-9_-]+' . | grep -v -E 'pkgs\.lib\b' || true; \
      exit 1; \
    fi
    if git ls-files -- '*.py' >/dev/null 2>&1; then \
      ruff check -- .; \
      black --check --line-length 100 --extend-exclude '(secrets/crypted|modules/user/gui/kitty/conf/tab_bar.py)' .; \
    fi
    # Optional guard: prefer `let exe = lib.getExe' pkgs.pkg "bin"; in "${exe} …" over direct ${pkgs.*}/bin paths
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
        | grep -v 'modules/user/mail/isync/default.nix' \
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
    git ls-files -z -- '*.sh' '*.bash' 2>/dev/null \
      | xargs -0 -r grep -lZ -m1 -E '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh' \
      | xargs -0 -r shellcheck -S warning -x
    # Optional guard: ensure each pkgs.* item in lists has an inline comment
    # Enable with: COMMENTS_GUARD=1 just lint
    if [ "${COMMENTS_GUARD:-}" = "1" ]; then \
      python3 scripts/comments_guard.py; \
    fi

lint-md *ARGS:
    set -eu
    if [ "$#" -gt 0 ]; then \
      markdownlint --config .markdownlint.yaml "$@"; \
    elif git ls-files -- '*.md' >/dev/null 2>&1; then \
      markdownlint --config .markdownlint.yaml .; \
    else \
      echo 'No Markdown files found'; \
    fi

hm-neg:
    home-manager switch --flake .#neg

hm-lite:
    home-manager switch --flake .#neg-lite

hm-dev-speed:
    # Enable dev-speed mode (env + feature defaults) and switch full profile
    HM_DEV_SPEED=1 home-manager switch --flake .#neg

hm-lite-speed:
    # Enable dev-speed mode (env + feature defaults) and switch lite profile
    HM_DEV_SPEED=1 home-manager switch --flake .#neg-lite

hm-build:
    # Build activation package without switching
    home-manager build --flake .#neg

docs:
    # Generate docs packages (OPTIONS.md, features-options.{md,json})
    HM_DOCS=1 nix build --no-link -L .#docs.${SYSTEM:-x86_64-linux}.options-md

hooks-enable:
    git config core.hooksPath .githooks

show-features:
    # Print flattened features for given check names (or default matrix)
    # Compatible with older `just` (no recipe args). Pass items via env var:
    #   NAMES="hm-eval-neg-retro-on hm-eval-neg-retro-off" just show-features
    # Or rely on defaults:
    #   just show-features
    # Filter only true values:
    #   ONLY_TRUE=1 just show-features
    set -eu
    sys=${SYSTEM:-x86_64-linux}
    if [ -n "${NAMES:-}" ]; then \
    items=(${NAMES}); \
    else \
    items=( \
      hm-eval-neg-retro-on \
      hm-eval-neg-retro-off \
      hm-eval-lite-retro-on \
      hm-eval-lite-retro-off \
      hm-eval-neg-nogui-retro-on \
      hm-eval-neg-nogui-retro-off \
      hm-eval-lite-nogui-retro-on \
      hm-eval-lite-nogui-retro-off \
      hm-eval-neg-noweb-retro-on \
      hm-eval-neg-noweb-retro-off \
      hm-eval-lite-noweb-retro-on \
      hm-eval-lite-noweb-retro-off \
    ); \
    fi
    for name in "${items[@]}"; do \
      echo "== ${name} (system=${sys}) =="; \
      out=$(nix build --no-link --print-out-paths ".#checks.${sys}.${name}"); \
      if command -v jq >/dev/null 2>&1; then \
        if [ "${ONLY_TRUE:-}" = "1" ]; then \
          jq -r 'to_entries|map(select(.value==true).key)|.[]' <"$out"; \
        else \
          jq . <"$out"; \
        fi; \
      else \
        cat "$out"; \
      fi; \
      echo; \
    done

hm-status:
    set -eu
    echo "== systemd --user failed units =="
    systemctl --user --failed || true
    echo
    echo "== recent user journal =="
    journalctl --user -b -n 120 --no-pager || true

xdg-report:
    # Size-sorted report for ~/.local/share, ~/.local/state, ~/.var/app
    # Env: RETENTION_DAYS (default 60), TOP_N (default 30), SKIP_BASENAMES, SKIP_PATHS
    RETENTION_DAYS=${RETENTION_DAYS:-60} TOP_N=${TOP_N:-30} bash scripts/xdg-report.sh

xdg-clean:
    # Clean caches older than RETENTION_DAYS and purge Zotero remnants
    # Env: RETENTION_DAYS (default 60), KEEP_CACHE_NAMES (default floorp), DRY_RUN (default 0)
    RETENTION_DAYS=${RETENTION_DAYS:-60} KEEP_CACHE_NAMES=${KEEP_CACHE_NAMES:-floorp} DRY_RUN=${DRY_RUN:-0} bash scripts/xdg-clean.sh

xdg-clean-dry:
    # Dry-run for cache+Zotero cleanup
    RETENTION_DAYS=${RETENTION_DAYS:-60} KEEP_CACHE_NAMES=${KEEP_CACHE_NAMES:-floorp} DRY_RUN=1 bash scripts/xdg-clean.sh

xdg-delete:
    # Delete explicit paths (guarded to $HOME)
    # Provide paths via TARGETS env or TARGETS_FILE, or pass as args after --
    set -eu
    if [ -n "${TARGETS:-}" ]; then \
      bash scripts/xdg-clean.sh delete ${TARGETS}; \
    elif [ -n "${TARGETS_FILE:-}" ]; then \
      bash scripts/xdg-clean.sh delete --from-file "${TARGETS_FILE}"; \
    elif [ "$#" -gt 0 ]; then \
      bash scripts/xdg-clean.sh delete "$@"; \
    else \
      echo 'Provide TARGETS="<paths>" or TARGETS_FILE=<file> or args after --' >&2; \
      exit 2; \
    fi

xdg-delete-targets:
    # Delete curated list from scripts/xdg-delete-targets.txt
    TARGETS_FILE=scripts/xdg-delete-targets.txt just xdg-delete

clean-caches:
    set -eu
    repo=$(git rev-parse --show-toplevel)
    find "$repo" -type f -name '*.zwc' -delete || true
    find "$repo" -type d -name '__pycache__' -prune -exec rm -rf {} + || true
    find "$repo" -type f -name '*.pyc' -delete || true
    rm -rf "$repo/nix/.config/home-manager/.cache" || true
    : "${XDG_CACHE_HOME:=$HOME/.cache}"
    : "${XDG_STATE_HOME:=$HOME/.local/state}"
    rm -rf "$XDG_CACHE_HOME/zsh" || true
    rm -rf "$XDG_CACHE_HOME/nu" "$XDG_CACHE_HOME/nushell" || true
    rm -f "$XDG_STATE_HOME/nushell/history.sqlite3"* || true

hm-bench:
    # Fast eval stats for baseline + no-GUI + no-Web matrices
    set -eu
    sys=${SYSTEM:-x86_64-linux}
    if [ -n "${NAMES:-}" ]; then \
      items=(${NAMES}); \
    else \
      items=( \
        hm-eval-neg-retro-off \
        hm-eval-lite-retro-off \
        hm-eval-neg-nogui-retro-off \
        hm-eval-lite-nogui-retro-off \
        hm-eval-neg-noweb-retro-off \
        hm-eval-lite-noweb-retro-off \
      ); \
    fi
    for name in "${items[@]}"; do \
      echo "== ${name} (system=${sys}) =="; \
      NIX_SHOW_STATS=1 nix build --no-link ".#checks.${sys}.${name}" -L || true; \
      echo; \
    done

hm-bench-fast:
    # Fast eval stats only for no-GUI/no-Web matrices
    set -eu
    sys=${SYSTEM:-x86_64-linux}
    items=( \
      hm-eval-neg-nogui-retro-off \
      hm-eval-lite-nogui-retro-off \
      hm-eval-neg-noweb-retro-off \
      hm-eval-lite-noweb-retro-off \
    )
    for name in "${items[@]}"; do \
      echo "== ${name} (system=${sys}) =="; \
      NIX_SHOW_STATS=1 nix build --no-link ".#checks.${sys}.${name}" -L || true; \
      echo; \
    done
