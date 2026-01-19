# Repository development helpers for NixOS workflows
set shell := ["bash", "-cu"]

# --- System-level docs/utilities -------------------------------------------------
# Generate aggregated options docs into docs/howto/*.md
gen-options:
    repo_root="$(git rev-parse --show-toplevel)"; \
    cd "$repo_root" && scripts/dev/gen-options.sh

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
    cd "$repo_root" && scripts/hw/cpu-recommend-masks.sh

# --- System Management -----------------------------------------------------------

# Rebuild and switch to the new system configuration
# Usage: just deploy [host]
deploy host="telfir":
    # Build system closure (fast, git-aware, user-cache)
    nix build .#nixosConfigurations.{{host}}.config.system.build.toplevel --out-link result
    # Update system profile
    sudo nix-env -p /nix/var/nix/profiles/system --set $(readlink -f result)
    # Switch to new configuration
    sudo ./result/bin/switch-to-configuration switch

# Deploy (Legacy/Slow) - keeps nh features like pretty print
deploy-nh host="telfir":
    nh os switch . --hostname {{host}}

# Deploy with maximum verbosity (logs + trace + verbose)
deploy-debug host="telfir":
    nh os switch . --hostname {{host}} -L -t -v

# Alias for deploy
switch host="telfir":
    just deploy {{host}}

# Show diff between last two generations
diff:
    @files=$(find /nix/var/nix/profiles -maxdepth 1 -name "system-*-link" | sort -V | tail -n 2); \
    nix run nixpkgs#nvd -- diff $files

# --- Repo-wide workflows ---------------------------------------------------------


fmt:
    repo_root="$(git rev-parse --show-toplevel)"; \
    cd "$repo_root" && nix fmt

check:
    repo_root="$(git rev-parse --show-toplevel)"; \
    nix flake check -L

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
    # Guard: avoid mkdir/touch/rm in ExecStartPre/ExecStart within systemd units
    # Prefer mkLocalBin or per-file force on managed files/wrappers.
    if grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
         'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules | \
       grep -v 'modules/dev/cachix/default.nix' | grep -q .; then \
      echo 'Found ExecStartPre/ExecStart with mkdir/touch/rm. Use mkLocalBin or per-file force instead.' >&2; \
      grep -R -nE --exclude-dir={.direnv,result,.git} --include='*.nix' --exclude='flake/checks.nix' --exclude='checks.nix' \
        'Exec(Start|Stop)(Pre|Post)[[:space:]]*=.*(mkdir(\s+-p)?|install(\s+-d)?|touch|rm[[:space:]]+-rf?)' modules \
        | grep -v 'modules/dev/cachix/default.nix' || true; \
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
    if git ls-files -- '*.py' >/dev/null 2>&1; then \
      ruff check -- .; \
      black --check --line-length 79 --extend-exclude '(secrets/home/crypted|modules/user/gui/kitty/conf/tab_bar.py|modules/user/gui/kitty/conf/scroll_mark.py|modules/user/gui/kitty/conf/search.py)' .; \
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
    just lint-annotations

# Check that all packages in environment.systemPackages have inline annotations
lint-annotations:
    repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; \
    bash "$repo_root/scripts/dev/check-package-annotations.sh" "$repo_root"

lint-md *ARGS:
    set -eu
    if [ "$#" -gt 0 ]; then \
      markdownlint --config .markdownlint.yaml "$@"; \
    elif [ -n "$$(git ls-files -- '*.md')" ]; then \
      markdownlint --config .markdownlint.yaml .; \
    else \
      echo 'No Markdown files found'; \
    fi

docs-modules:
    # Generate modules documentation (opt-in)
    nix build .#docs-modules -o .result-docs
    mkdir -p docs/howto
    cp -f .result-docs/modules.md docs/howto/modules.md
    rm -f .result-docs
    chmod +w docs/howto/modules.md
    echo "Generated docs/howto/modules.md"

hooks-enable:
    git config core.hooksPath .githooks

show-features:
    # Print flattened features for given check names
    # Pass items via env var:
    #   NAMES="nixos-eval-telfir" just show-features
    # Filter only true values:
    #   ONLY_TRUE=1 just show-features
    set -eu
    sys=${SYSTEM:-x86_64-linux}
    if [ -n "${NAMES:-}" ]; then \
    items=(${NAMES}); \
    else \
    items=(nixos-eval-telfir); \
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
    rm -rf "$XDG_CACHE_HOME/nu" "$XDG_CACHE_HOME/nushell" || true
    rm -f "$XDG_STATE_HOME/nushell/history.sqlite3"* || true

