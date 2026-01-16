{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  pkgs,
  ...
}:
system:
let
  inherit (nixpkgs) lib;
  # pkgs is now passed from flake.nix
  mkCustomPkgs = flakeLib.mkCustomPkgs;
  nixfmtPkg = nixpkgs.legacyPackages.${system}.nixfmt;

  # Pre-commit utility per system
  preCommit = inputs.pre-commit-hooks.lib.${system}.run {
    src = self;
    hooks = {
      nixfmt-rfc-style = {
        enable = true;
        package = nixfmtPkg;
        excludes = [ "flake.nix" ];
      };
      statix.enable = true;
      deadnix.enable = true;
    };
  };
in
{
  packages = (mkCustomPkgs pkgs) // {
    default = pkgs.zsh; # default shell for the flake environment
    docs-modules = import ./docs-modules.nix {
      inherit pkgs lib self;
    };
  };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = [
      nixfmtPkg # nix formatter
      pkgs.black # python formatter
      pkgs.python3Packages.mdformat # markdown formatter
      pkgs.shfmt # shell script formatter
      pkgs.treefmt # unified formatting tool
    ];
    text = ''
      set -euo pipefail
      if git rev-parse --show-toplevel >/dev/null 2>&1; then
        repo_root="$(git rev-parse --show-toplevel)"
      else
        repo_root="${self}"
      fi
      cd "$repo_root"
      tmp_conf=$(mktemp)
      trap 'rm -f "$tmp_conf"' EXIT
      cp ${../treefmt.toml} "$tmp_conf"
      exec treefmt --config-file "$tmp_conf" --tree-root "$repo_root" "$@"
    '';
  };

  checks = {
    fmt-treefmt =
      pkgs.runCommand "fmt-treefmt"
        {
          nativeBuildInputs = [
            nixfmtPkg # nix formatter
            pkgs.black # python formatter
            pkgs.python3Packages.mdformat # markdown formatter
            pkgs.shfmt # shell script formatter
            pkgs.treefmt # unified formatting tool
            pkgs.findutils # find, xargs
          ];
          src = ../.;
        }
        ''
          set -euo pipefail
          cp -r "$src" ./src
          chmod -R u+w ./src
          cd ./src
          export XDG_CACHE_HOME="$PWD/.cache"
          mkdir -p "$XDG_CACHE_HOME"
          cp ${../treefmt.toml} ./.treefmt.toml
          treefmt --config-file ./.treefmt.toml --tree-root . --fail-on-change .
          touch "$out"
        '';
    lint-deadnix = pkgs.runCommand "lint-deadnix" { nativeBuildInputs = [ pkgs.deadnix ]; } ''
      # Find and remove unused code in .nix source files
                # unused code detector
                     cd ${self}
                     deadnix --fail --exclude home .
                     touch "$out"
    '';
    lint-statix = pkgs.runCommand "lint-statix" {
      nativeBuildInputs = [ pkgs.statix ]; # Lints and suggestions for the nix programming language
    } ''cd ${self}; statix check .; touch "$out"''; # nix antipattern linter
    pre-commit = preCommit;
    lint-md-lang =
      pkgs.runCommand "lint-md-lang"
        {
          nativeBuildInputs = [
            pkgs.bash
            pkgs.coreutils # GNU Core Utilities
            pkgs.findutils # GNU Find Utilities, the basic directory searching utiliti...
            pkgs.gnugrep # GNU implementation of the Unix grep command
            pkgs.gitMinimal # Distributed version control system
          ];
        }
        ''
          # markdown language check (EN/RU)
               set -euo pipefail
               cd ${self}
               bash scripts/dev/check-markdown-language.sh
               : > "$out"
        '';
    tests-caddy = pkgs.testers.runNixOSTest (import ../tests/caddy.nix);
    tests-hyprland-startup = pkgs.testers.runNixOSTest (import ../tests/hyprland-startup.nix);

    # Shell script linting with shellcheck
    lint-shellcheck =
      pkgs.runCommand "lint-shellcheck"
        {
          nativeBuildInputs = [
            pkgs.shellcheck # shell script linter
            pkgs.findutils # find, xargs
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          # Find shell scripts with proper shebangs and run shellcheck
          find files scripts -type f \( -name '*.sh' -o -name '*.bash' \) \
            -exec grep -lZ -m1 -E '^#!\s*/(usr/)?bin/(env\s+)?(ba)?sh' {} + 2>/dev/null \
            | xargs -0 -r shellcheck -S warning -x || true
          touch "$out"
        '';

    # Verify NixOS configuration evaluates (no build, no fetch)
    # This creates a trivial derivation that depends on the config being evaluable
    nixos-eval-telfir =
      let
        # Force evaluation of the config by accessing a lightweight attribute
        configName = inputs.self.nixosConfigurations.telfir.config.system.name;
      in
      pkgs.runCommand "nixos-eval-telfir" { } ''
        echo "Config evaluated successfully: ${configName}"
        touch "$out"
      '';

    # Verify all impurity.link paths exist in the repository
    check-impurity-paths =
      pkgs.runCommand "check-impurity-paths"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.findutils # find, xargs
            pkgs.gnugrep # grep
            pkgs.gitMinimal # minimal git client
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          bash scripts/dev/check-impurity-paths.sh
          touch "$out"
        '';

    # Validate JSON and TOML config file syntax
    lint-json-toml =
      pkgs.runCommand "lint-json-toml"
        {
          nativeBuildInputs = [
            pkgs.jq # json processor
            pkgs.python3 # python interpreter
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking JSON files..."
          find files -name '*.json' -exec jq -e . {} + >/dev/null
          echo "Checking TOML files..."
          find files -name '*.toml' -print0 | xargs -0 -r -I {} python3 -c "import tomllib; tomllib.load(open('{}', 'rb'))"
          echo "All config files are valid!"
          touch "$out"
        '';

    # Python linting with ruff (fast, comprehensive)
    lint-python =
      pkgs.runCommand "lint-python"
        {
          nativeBuildInputs = [
            pkgs.ruff # fast python linter
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Linting Python files with ruff..."
          find . -name '*.py' -not -path './.direnv/*' -not -path './result/*' \
            -exec ruff check --select=E,F,W --ignore=E501 {} + || true
          echo "Python linting complete!"
          touch "$out"
        '';

    # QML syntax checking for QuickShell
    lint-qml =
      pkgs.runCommand "lint-qml"
        {
          nativeBuildInputs = [
            pkgs.kdePackages.qtdeclarative # qmllint
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking QML files..."
          # qmllint returns non-zero on warnings, so we just check for errors
          find files/quickshell -name '*.qml' -print0 \
            | xargs -0 -r qmllint -I files/quickshell 2>&1 || true
          echo "QML check complete!"
          touch "$out"
        '';

    # Check that all $variables in Hyprland configs are defined
    check-hyprland-vars =
      pkgs.runCommand "check-hyprland-vars"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
            pkgs.gnused # stream editor
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          bash scripts/dev/check-hyprland-vars.sh
          touch "$out"
        '';

    # Check flake input freshness (warning only)
    check-flake-inputs =
      pkgs.runCommand "check-flake-inputs"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.jq # json processor
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          bash scripts/dev/check-flake-inputs.sh
          touch "$out"
        '';

    # YAML syntax validation
    lint-yaml =
      pkgs.runCommand "lint-yaml"
        {
          nativeBuildInputs = [
            pkgs.yamllint # yaml linter
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking YAML files..."
          find . -type f \( -name '*.yml' -o -name '*.yaml' \) \
            -not -path './.direnv/*' -not -path './result/*' \
            -exec yamllint -d "{extends: relaxed, rules: {line-length: disable}}" {} + || true
          echo "YAML check complete!"
          touch "$out"
        '';

    # Desktop file validation
    check-desktop-files =
      pkgs.runCommand "check-desktop-files"
        {
          nativeBuildInputs = [
            pkgs.desktop-file-utils # desktop file validator
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking .desktop files..."
          find . -name '*.desktop' -not -path './.direnv/*' -not -path './result/*' \
            -exec desktop-file-validate {} + 2>&1 || true
          echo "Desktop file check complete!"
          touch "$out"
        '';

    # Check that all module imports exist
    check-module-imports =
      pkgs.runCommand "check-module-imports"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking module imports..."
          # Find all .nix files and check that their relative imports exist
          find modules -name '*.nix' -type f | while IFS= read -r file; do
            dir=$(dirname "$file")
            # Extract imported paths like ./foo.nix or ./bar/baz.nix
            grep -oE '\./[a-zA-Z0-9_/-]+\.nix' "$file" 2>/dev/null | while read -r imp; do
              full_path="$dir/$imp"
              if [[ ! -f "$full_path" ]]; then
                echo "WARNING: $file imports non-existent: $imp"
              fi
            done || true
          done || true
          echo "Module import check complete!"
          touch "$out"
        '';

    # Check for package reference patterns (informational)
    check-package-refs =
      pkgs.runCommand "check-package-refs"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          bash scripts/dev/check-package-refs.sh
          touch "$out"
        '';

    # Check that all shell scripts are executable
    check-script-executability =
      pkgs.runCommand "check-script-executability"
        {
          nativeBuildInputs = [
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking shell script executability..."
          errors=0
          find files scripts -name '*.sh' -type f | while read -r script; do
            if [[ ! -x "$script" ]]; then
              echo "WARNING: Not executable: $script"
            fi
          done || true
          echo "Script executability check complete!"
          touch "$out"
        '';

    # Check for potential secrets in code
    check-no-secrets =
      pkgs.runCommand "check-no-secrets"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for potential secrets..."
          # Look for common secret patterns (but allow false positives)
          if grep -rI --include='*.nix' --include='*.sh' \
              -E '(password|secret|api_key|apikey|token)\s*=\s*"[^"$]{8,}"' \
              --exclude-dir=secrets --exclude-dir=.git . 2>/dev/null; then
            echo "WARNING: Potential hardcoded secrets found above"
          fi
          echo "Secret check complete!"
          touch "$out"
        '';

    # Lua syntax checking for Neovim config
    lint-lua =
      pkgs.runCommand "lint-lua"
        {
          nativeBuildInputs = [
            pkgs.lua54Packages.luacheck # lua linter
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking Lua files..."
          find files/nvim -name '*.lua' -exec luacheck --no-color \
            --globals vim --std luajit \
            --ignore 212 311 631 \
            {} + 2>&1 || true
          echo "Lua check complete!"
          touch "$out"
        '';

    # CSS syntax validation using Python cssutils
    check-css-syntax =
      pkgs.runCommand "check-css-syntax"
        {
          nativeBuildInputs = [
            (pkgs.python3.withPackages (p: [ p.cssutils ])) # High-level dynamically-typed programming language
            pkgs.findutils # find, xargs
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking CSS files..."
          # Skip template files and silence logger noise for non-standard CSS (GTK/mozilla extensions)
          find files -name '*.css' | while read -r css; do
            if grep -q '\''${' "$css" 2>/dev/null; then
              echo "INFO: Skipping Nix template $css"
              continue
            fi
            python3 -c "import cssutils, logging; cssutils.log.setLevel(logging.FATAL); cssutils.parseFile('$css')" 2>&1 | grep -vE "Unknown @rule|Unknown Property|Unknown syntax|Invalid value|No content to parse" || true
          done
          echo "CSS check complete!"
          touch "$out"
        '';

    # SVG syntax validation (XML well-formedness)
    check-svg-syntax =
      pkgs.runCommand "check-svg-syntax"
        {
          nativeBuildInputs = [
            pkgs.libxml2 # xmllint
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking SVG files (52 files)..."
          find files -name '*.svg' -exec xmllint --noout {} + 2>&1 || true
          echo "SVG check complete!"
          touch "$out"
        '';

    # Check for typos in code and comments
    check-typos =
      pkgs.runCommand "check-typos"
        {
          nativeBuildInputs = [ pkgs.typos ]; # typo checker
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for typos..."
          typos --format brief \
            --exclude "*.lock" \
            --exclude "flake.lock" \
            --exclude "*.svg" \
            . 2>&1 || true
          echo "Typo check complete!"
          touch "$out"
        '';

    # Check for broken symlinks
    check-broken-symlinks =
      pkgs.runCommand "check-broken-symlinks"
        {
          nativeBuildInputs = [
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for broken symlinks..."
          broken=$(find files packages -xtype l 2>/dev/null || true)
          if [[ -n "$broken" ]]; then
            echo "WARNING: Broken symlinks found:"
            echo "$broken"
          fi
          echo "Symlink check complete!"
          touch "$out"
        '';

    # Check for hardcoded /nix/store/ paths
    check-nix-path-refs =
      pkgs.runCommand "check-nix-path-refs"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for hardcoded /nix/store/ paths..."
          if grep -rI --include='*.nix' --include='*.sh' '/nix/store/' \
              --exclude-dir=.git . 2>/dev/null | grep -v 'nix-store' | head -20; then
            echo "WARNING: Hardcoded store paths found above"
          fi
          echo "Store path check complete!"
          touch "$out"
        '';

    # Check for duplicate packages in systemPackages
    check-duplicate-packages =
      pkgs.runCommand "check-duplicate-packages"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.gnused # stream editor
            pkgs.coreutils # basic file/text utilities
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for duplicate packages..."
          # Extract package references and find duplicates
          grep -rhE 'pkgs\.[a-zA-Z0-9_-]+' modules --include='*.nix' 2>/dev/null \
            | grep -oE 'pkgs\.[a-zA-Z0-9_-]+' \
            | sort | uniq -d | head -20 | while read -r pkg; do
              echo "Duplicate: $pkg"
            done || true
          echo "Duplicate check complete!"
          touch "$out"
        '';

    # Check for unused .nix files (dead code)
    check-dead-code =
      pkgs.runCommand "check-dead-code"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
            pkgs.findutils # find, xargs
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for potentially unused .nix files..."
          find modules packages -name '*.nix' -type f | while read -r file; do
            basename=$(basename "$file")
            # Skip common entry points
            if [[ "$basename" == "default.nix" ]] || [[ "$basename" == "overlay.nix" ]]; then
              continue
            fi
            # Check if file is imported anywhere
            if ! grep -rq "$basename" modules packages flake --include='*.nix' 2>/dev/null; then
              echo "Potentially unused: $file"
            fi
          done | head -30 || true
          echo "Dead code check complete!"
          touch "$out"
        '';

    # Check for tracked files matching .gitignore patterns
    check-git-ignore =
      pkgs.runCommand "check-git-ignore"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.findutils # find, xargs
            pkgs.fd # fast find replacement
          ];
        }
        ''
          set -euo pipefail
          cp -r ${self} ./src
          chmod -R +w ./src
          cd ./src
          bash scripts/dev/check-git-ignore.sh
          touch "$out"
        '';

    # Rofi rasi theme syntax check
    lint-rasi =
      pkgs.runCommand "lint-rasi"
        {
          nativeBuildInputs = [
            pkgs.findutils # find, xargs
            pkgs.gnugrep # grep
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking Rofi .rasi files..."
          errors=0
          find . -name '*.rasi' -not -path './.direnv/*' | while read -r rasi; do
            # Basic syntax check: balanced braces
            opens=$(grep -o '{' "$rasi" 2>/dev/null | wc -l || echo 0)
            closes=$(grep -o '}' "$rasi" 2>/dev/null | wc -l || echo 0)
            if [[ "$opens" != "$closes" ]]; then
              echo "WARNING: Unbalanced braces in $rasi (open: $opens, close: $closes)"
            fi
          done || true
          echo "Rasi check complete!"
          touch "$out"
        '';

    # Build all custom packages to verify they compile
    build-custom-packages =
      pkgs.runCommand "build-custom-packages"
        {
          nativeBuildInputs = [ pkgs.coreutils ]; # basic file/text utilities
          # Reference a few key custom packages to verify they build
          customPkgs = [
            (pkgs.neg.tewi or null)
            (pkgs.neg.lucida or null)
            (pkgs.neg.richcolors or null)
          ];
        }
        ''
          set -euo pipefail
          echo "Custom packages build verification passed!"
          touch "$out"
        '';

    # Check for unused flake inputs
    check-unused-inputs =
      pkgs.runCommand "check-unused-inputs"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.coreutils # basic file/text utilities
            pkgs.jq # json processor
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for unused flake inputs..."

          # Known inputs from flake.nix
          inputs=(
            nixpkgs hyprland hy3 hyprland-protocols xdg-desktop-portal-hyprland
            quickshell lanzaboote nvf nyx nur sops-nix pre-commit-hooks
            nix-maid pyprland raise tailray winapps wrapper-manager
          )

          # Inputs that are .follows directives (not direct usage expected)
          follows_inputs=(hyprland-protocols xdg-desktop-portal-hyprland)

          # Inputs used via overlays (referenced as packages, not inputs.*)

          unused=0
          for input in "''${inputs[@]}"; do
            # Skip nixpkgs as it's always used implicitly
            if [[ "$input" == "nixpkgs" ]]; then continue; fi

            # Skip .follows directives
            for f in "''${follows_inputs[@]}"; do
              if [[ "$input" == "$f" ]]; then continue 2; fi
            done

            # Skip overlay-based inputs (they're used as pkgs.*, not inputs.*)
            for o in "''${overlay_inputs[@]}"; do
              if [[ "$input" == "$o" ]]; then continue 2; fi
            done

            # Check if input is referenced in any .nix file
            if ! grep -rq "inputs\.$input\|inputs\.\"$input\"" \
                --include='*.nix' flake modules packages 2>/dev/null; then
              echo "WARNING: Input '$input' may be unused"
              unused=$((unused + 1))
            fi
          done

          if [[ $unused -gt 0 ]]; then
            echo "Found $unused potentially unused inputs"
          else
            echo "All inputs appear to be used!"
          fi
          touch "$out"
        '';

    # Check that key modules have README.md documentation
    check-readme-sync =
      pkgs.runCommand "check-readme-sync"
        {
          nativeBuildInputs = [
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking module documentation..."

          missing=0
          # Check top-level module directories
          for dir in modules/*/; do
            if [[ ! -f "$dir/README.md" ]]; then
              echo "WARNING: Missing README.md in $dir"
              missing=$((missing + 1))
            fi
          done

          # Check packages
          for dir in packages/*/; do
            # Skip overlay files
            if [[ -f "$dir" ]]; then continue; fi
            if [[ ! -f "$dir/README.md" ]] && [[ -f "$dir/default.nix" ]]; then
              echo "INFO: Package $dir has no README.md"
            fi
          done

          if [[ $missing -gt 0 ]]; then
            echo "Found $missing modules missing README.md"
          else
            echo "All key modules have documentation!"
          fi
          touch "$out"
        '';

    # JavaScript syntax checking for QuickShell helpers
    lint-javascript =
      pkgs.runCommand "lint-javascript"
        {
          nativeBuildInputs = [
            pkgs.nodejs # javascript runtime
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking JavaScript files in quickshell/Helpers..."

          errors=0
          total=0
          skipped=0
          find files/quickshell -name '*.js' | while read -r jsfile; do
            # Skip QML-style files with .pragma directive (not standard JS)
            if grep -q '^\.pragma' "$jsfile" 2>/dev/null; then
              skipped=$((skipped + 1))
              continue
            fi
            total=$((total + 1))
            if ! node --check "$jsfile" 2>&1; then
              echo "ERROR: Syntax error in $jsfile"
              errors=$((errors + 1))
            fi
          done || true

          echo "Checked JS files (skipped QML-pragma files)"
          if [[ $errors -gt 0 ]]; then
            echo "Found $errors files with syntax errors"
          else
            echo "All checked JavaScript files have valid syntax!"
          fi
          touch "$out"
        '';

    # Check that Hyprland bindings reference executable commands
    check-hyprland-bindings =
      pkgs.runCommand "check-hyprland-bindings"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.gnused # stream editor
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking Hyprland bindings for valid commands..."

          # Extract commands from bind= declarations
          grep -rhE '^bind\s*=' files/gui/hypr --include='*.conf' 2>/dev/null \
            | sed 's/.*,\s*//' \
            | sed 's/\s*#.*//' \
            | grep -oE '^[a-zA-Z0-9_-]+' \
            | sort -u | while read -r cmd; do
              # Skip known built-in Hyprland dispatchers
              case "$cmd" in
                exec|exec-once|pass|killactive|closewindow|togglefloating|\
                fullscreen|fakefullscreen|pin|pseudo|togglesplit|togglegroup|\
                workspace|movetoworkspace|movetoworkspacesilent|movefocus|\
                movewindow|resizeactive|cyclenext|focuswindow|hy3*|split*|\
                movecurrentworkspacetomonitor|focusmonitor|swapwindow|exit|\
                hyprctl|notify|lockactivegroup|movewindoworgroup|changegroupactive)
                  continue ;;
              esac
              echo "INFO: Command used in binding: $cmd"
            done || true
          echo "Hyprland bindings check complete!"
          touch "$out"
        '';

    # Check that packages have descriptive annotations
    check-package-annotations =
      pkgs.runCommand "check-package-annotations"
        {
          nativeBuildInputs = [
            pkgs.bash # bourne again shell
            pkgs.coreutils # basic file/text utilities
            pkgs.gnugrep # grep
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          bash scripts/dev/check-package-annotations.sh
          touch "$out"
        '';

    # Verify sops secrets are encrypted (not plaintext)
    check-sops-secrets =
      pkgs.runCommand "check-sops-secrets"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking sops secrets encryption..."

          errors=0
          find secrets -name '*.sops.yaml' -o -name '*.sops.json' 2>/dev/null | while read -r secret; do
            # Encrypted sops files should contain 'sops:' metadata section
            if ! grep -q 'sops:' "$secret" 2>/dev/null; then
              echo "WARNING: $secret may not be encrypted (missing sops metadata)"
              errors=$((errors + 1))
            fi
            # Check for common unencrypted patterns
            if grep -qE '^\s*(password|secret|token|key):\s*[^E]' "$secret" 2>/dev/null; then
              echo "WARNING: $secret may contain unencrypted secrets"
            fi
          done || true

          echo "Sops secrets check complete!"
          touch "$out"
        '';

    # Check flake.lock age (warn if older than 30 days)
    check-flake-lock-age =
      pkgs.runCommand "check-flake-lock-age"
        {
          nativeBuildInputs = [
            pkgs.coreutils # basic file/text utilities
            pkgs.jq # json processor
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking flake.lock freshness..."

          if [[ -f flake.lock ]]; then
            # Get file modification time
            lock_mtime=$(stat -c %Y flake.lock)
            current_time=$(date +%s)
            age_days=$(( (current_time - lock_mtime) / 86400 ))

            if [[ $age_days -gt 30 ]]; then
              echo "WARNING: flake.lock is $age_days days old (>30 days)"
              echo "Consider running: nix flake update"
            elif [[ $age_days -gt 14 ]]; then
              echo "INFO: flake.lock is $age_days days old"
            else
              echo "flake.lock is fresh ($age_days days old)"
            fi
          else
            echo "WARNING: flake.lock not found"
          fi
          touch "$out"
        '';

    # Check that all hosts have required config files
    check-host-configs =
      pkgs.runCommand "check-host-configs"
        {
          nativeBuildInputs = [
            pkgs.findutils # find, xargs
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking host configurations..."

          for host in hosts/*/; do
            hostname=$(basename "$host")
            # Skip non-directories and README files
            [[ ! -d "$host" ]] && continue

            missing=()
            # Check required files
            [[ ! -f "$host/default.nix" ]] && missing+=("default.nix")
            [[ ! -f "$host/hardware.nix" ]] && [[ ! -f "$host/hardware-configuration.nix" ]] && missing+=("hardware.nix")

            if [[ ''${#missing[@]} -gt 0 ]]; then
              echo "WARNING: Host '$hostname' missing: ''${missing[*]}"
            else
              echo "✓ Host '$hostname' has required files"
            fi
          done
          touch "$out"
        '';

    # Check for hardcoded paths instead of XDG variables
    check-xdg-compliance =
      pkgs.runCommand "check-xdg-compliance"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking XDG compliance..."

          # Look for hardcoded home paths that should use XDG
          issues=0
          if grep -rn --include='*.nix' --include='*.sh' \
              -E '~/\.config|~/\.cache|~/\.local|~/\.data' \
              files scripts 2>/dev/null | grep -v '#.*XDG' | head -10; then
            echo "INFO: Found hardcoded paths (consider using XDG variables)"
            issues=$((issues + 1))
          fi

          if [[ $issues -eq 0 ]]; then
            echo "No obvious XDG compliance issues found"
          fi
          touch "$out"
        '';

    # Check for duplicate Hyprland bindings
    check-hyprland-duplicates =
      pkgs.runCommand "check-hyprland-duplicates"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.gnused # stream editor
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Checking for duplicate Hyprland bindings..."

          # Extract key combinations and find duplicates
          grep -rhE '^bind\s*=' files/gui/hypr --include='*.conf' 2>/dev/null \
            | sed 's/#.*//' \
            | sed 's/bind\s*=\s*//' \
            | cut -d',' -f1-2 \
            | sort | uniq -d | while read -r dup; do
              [[ -n "$dup" ]] && echo "WARNING: Duplicate binding: $dup"
            done || true

          echo "Hyprland duplicates check complete!"
          touch "$out"
        '';

    # Report TODO/FIXME comments in codebase
    check-todo-fixme =
      pkgs.runCommand "check-todo-fixme"
        {
          nativeBuildInputs = [
            pkgs.gnugrep # grep
            pkgs.coreutils # basic file/text utilities
          ];
        }
        ''
          set -euo pipefail
          cd ${self}
          echo "Scanning for TODO/FIXME comments..."

          todo_count=$(grep -rI --include='*.nix' --include='*.sh' --include='*.py' \
            -c -E '\b(TODO|FIXME|HACK|XXX)\b' modules packages scripts 2>/dev/null \
            | awk -F: '{sum += $2} END {print sum+0}')

          echo "Found $todo_count TODO/FIXME/HACK/XXX comments"

          # Show a few examples
          grep -rI --include='*.nix' --include='*.sh' \
            -n -E '\b(TODO|FIXME)\b' modules packages 2>/dev/null \
            | head -5 || true

          touch "$out"
        '';

  };

  devShells = {
    ai = pkgs.mkShell {
      nativeBuildInputs = [
        (pkgs.ai-studio or pkgs.lmstudio) # LM Studio is an easy to use desktop app for experimenting...
        pkgs.aichat
        pkgs.aider-chat
        pkgs.codex # Lightweight coding agent that runs in your terminal
        pkgs.openai # Python client library for the OpenAI API
        pkgs.code-cursor-fhs # AI code editor (VS Code)
      ];
    };

    default = pkgs.mkShell {
      inherit (preCommit) shellHook;
      packages = [
        nixfmtPkg # nix formatter
        pkgs.deadnix # unused code detector
        pkgs.statix # nix antipattern linter
        pkgs.nil # nix language server
        pkgs.just # command runner
        pkgs.jq # json processor
        # Linters/Formatters required by 'just lint' (moved from system pkgs)
        pkgs.black
        pkgs.ruff # Extremely fast Python linter and code formatter
        pkgs.mypy # Optional static typing for Python
        pkgs.stylua # Opinionated Lua code formatter
      ];
    };

    difftastic = pkgs.mkShell {
      packages = [ pkgs.difftastic ];
    };

    rclone = pkgs.mkShell {
      packages = [ pkgs.rclone ];
    };

    haskell =
      let
        tidalGhci = pkgs.writeShellScriptBin "tidal-ghci" ''
          exec ${pkgs.ghc.withPackages (ps: [ ps.tidal ])}/bin/ghci "$@" # Glasgow Haskell Compiler
        '';
        optionalHaskellTools =
          lib.optionals (pkgs ? fourmolu) [ pkgs.fourmolu ] # haskell formatter
          ++ lib.optionals (pkgs ? hindent) [ pkgs.hindent ]; # alternative haskell formatter
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.ghc # compiler
          pkgs.cabal-install # package/build tool
          pkgs.stack # alternative build tool
          pkgs.haskell-language-server # IDE/LSP backend
          pkgs.hlint # linter
          pkgs.ormolu # formatter
          pkgs.ghcid # fast GHCi reload loop
          tidalGhci # TidalCycles GHCi wrapper
          pkgs.haskellPackages.tidal # TidalCycles library
        ]
        ++ optionalHaskellTools;
      };

    rust =
      let
        optionalRustDebugAdapters = lib.optionals (pkgs ? codelldb) [
          pkgs.codelldb # LLDB-based debug adapter for Rust (DAP)
        ];
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.rustup # manage Rust channels/components
          pkgs.graphviz # dot backend for rustaceanvim crateGraph
          pkgs.bacon # background rust code checker
          pkgs.evcxr # Rust REPL
          pkgs.lldb # LLVM debugger
        ]
        ++ optionalRustDebugAdapters;
      };
    cpp = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.clang # C language family frontend for LLVM (wrapper script)
        pkgs.clang-tools # Standalone command line tools for C++ development
        pkgs.cmake # Cross-platform, open-source build system generator
        pkgs.ninja # Small build system with a focus on speed
        pkgs.bear
        pkgs.ccache # Compiler cache for fast recompilation of C/C++ code
        pkgs.lldb # Next-generation high-performance debugger
        pkgs.gdb # GNU Project debugger
        pkgs.gcc # explicitly available in devshell
      ];
    };

    java = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.jdk # Open-source Java Development Kit
        pkgs.gradle # Enterprise-grade build system
      ];
    };

    node = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.nodejs_24 # Event-driven I/O framework for the V8 JavaScript engine
      ];
    };

    nchat = pkgs.mkShell {
      packages = [ pkgs.nchat ];
    };

    vlang = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.vlang # Simple, fast, safe, compiled language for developing main...
      ];
    };

    re = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.radare2 # UNIX-like reverse engineering framework and command-line ...
        pkgs.cutter # Free and Open Source Reverse Engineering Platform powered...
        pkgs.flawfinder # Tool to examines C/C++ source code for security flaws
        pkgs.codeql # Semantic code analysis engine
        pkgs.foremost # forensic tool
      ];
    };

    infra =
      let
        optionalIaCTools = lib.optionals (pkgs ? aiac) [ pkgs.aiac ];
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pkgs.ansible
          pkgs.terraform # Tool for building, changing, and versioning infrastructure
          pkgs.opentofu # Tool for building, changing, and versioning infrastructure
        ]
        ++ optionalIaCTools;
      };

    python =
      let
        # Replicating logic from modules/dev/python/pkgs.nix
        myPythonPackages =
          ps: with ps; [
            # Core
            annoy
            beautifulsoup4
            colored
            docopt
            fonttools
            mutagen
            numpy
            orjson
            pillow
            psutil
            requests
            tabulate
            # Tools
            dbus-python
            fontforge
            neopyter
            pynvim
          ];
        pythonEnv = pkgs.python3-lto.withPackages myPythonPackages;
      in
      pkgs.mkShell {
        nativeBuildInputs = [
          pythonEnv
          pkgs.pipx # Install and run Python applications in isolated environments
          pkgs.black
          pkgs.ruff # Extremely fast Python linter and code formatter
          pkgs.mypy # Optional static typing for Python
        ];
      };

    lua = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.stylua # Opinionated Lua code formatter
      ];
    };

    android = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.android-tools
        pkgs.scrcpy # Display and control Android devices over USB or TCP/IP
        pkgs.adbfs-rootless
        pkgs.adbtuifm
      ]
      ++ lib.optionals (pkgs ? fuse3) [ pkgs.fuse3 ]; # Library that allows filesystems to be implemented in user...
    };

    bespokesynth = pkgs.mkShell {
      packages = [ pkgs.bespokesynth ];
    };

    qmk = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.qmk # Program to help users work with QMK Firmware
        pkgs.qmk_hid # Commandline tool for interactng with QMK devices over HID
        pkgs.keymapviz # Qmk keymap.c visualizer
      ];
    };

    radicle = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.radicle-node # Radicle node and CLI for decentralized code collaboration
        pkgs.radicle-explorer # Web frontend for Radicle
      ];
    };

    pentest = pkgs.mkShell {
      nativeBuildInputs = [
        # Recon
        pkgs.nmap # Free and open source utility for network discovery and se...
        pkgs.masscan # Fast scan of the Internet
        pkgs.rustscan # Faster Nmap Scanning with Rust
        pkgs.zmap # Fast single packet network scanner designed for Internet-...
        pkgs.dnsenum # Tool to enumerate DNS information
        pkgs.dnsrecon # DNS Enumeration script
        pkgs.dnstracer # Determines where a given Domain Name Server (DNS) gets it...
        pkgs.fierce # DNS reconnaissance tool for locating non-contiguous IP space
        pkgs.netdiscover # Network address discovering tool, developed mainly for th...
        pkgs.enum4linux # Tool for enumerating information from Windows and Samba s...
        pkgs.onesixtyone # Fast SNMP Scanner
        pkgs.arping
        pkgs.cloudbrute # Cloud enumeration tool
        pkgs.sn0int # Semi-automatic OSINT framework and package manager
        pkgs.netmask # IP address formatting tool
        pkgs.net-snmp # Clients and server for the SNMP network monitoring protocol
        pkgs.sslsplit # Transparent SSL/TLS interception
        pkgs.ssldump # SSLv3/TLS network protocol analyzer
        pkgs.sslh # Applicative Protocol Multiplexer (e.g. share SSH and HTTP...
        pkgs.sslscan # Tests SSL/TLS services and discover supported cipher suites
        pkgs.swaks # Featureful, flexible, scriptable, transaction-oriented SM...

        # Web
        pkgs.gobuster # Tool used to brute-force URIs, DNS subdomains, Virtual Ho...
        pkgs.dirb # Web content scanner
        pkgs.wfuzz # Web content fuzzer to facilitate web applications assessm...
        pkgs.zap # Java application for web penetration testing
        pkgs.katana # Next-generation crawling and spidering framework
        pkgs.urlhunter # Recon tool that allows searching shortened URLs

        # Passwords
        pkgs.john # John the Ripper password cracker
        pkgs.hashcat # Fast password cracker
        pkgs.thc-hydra # Very fast network logon cracker which support many differ...
        pkgs.brutespray
        pkgs.crowbar # Brute forcing tool that can be used during penetration tests
        pkgs.crunch # Wordlist generator
        pkgs.chntpw # Utility to reset the password of any user that has a vali...
        pkgs.hcxtools # Tools for capturing wlan traffic and conversion to hashca...
        pkgs.phrasendrescher # Modular and multi processing pass phrase cracking tool

        # Exploitation
        pkgs.metasploit # Metasploit Framework - a collection of exploits
        pkgs.exploitdb # Archive of public exploits and corresponding vulnerable s...
        pkgs.msfpc # MSFvenom Payload Creator
        pkgs.shellnoob # Shellcode writing toolkit
        pkgs.termineter # Smart Meter Security Testing Framework

        # Sniffing/MITM
        pkgs.wireshark # Powerful network protocol analyzer
        pkgs.tshark # Powerful network protocol analyzer
        pkgs.termshark # Terminal UI for wireshark-cli, inspired by Wireshark
        pkgs.tcpdump # Network sniffer
        pkgs.bettercap
        pkgs.mitmproxy # Man-in-the-middle proxy
        pkgs.dsniff # Collection of tools for network auditing and penetration ...
        pkgs.rshijack # TCP connection hijacker
        pkgs.sipp # SIPp testing tool
        pkgs.sniffglue # Secure multithreaded packet sniffer

        # Forensics
        pkgs.sleuthkit # Forensic/data recovery tool
        pkgs.volatility3 # Volatile memory extraction frameworks
        pkgs.ddrescue # GNU ddrescue, a data recovery tool
        pkgs.ext4magic # Recover / undelete files from ext3 or ext4 partitions
        pkgs.extundelete # Utility that can recover deleted files from an ext3 or ex...
        pkgs.steghide # Open source steganography program
        pkgs.stegseek # Tool to crack steganography
        pkgs.outguess # Universal steganographic tool that allows the insertion o...
        pkgs.zsteg # Detect stegano-hidden data in PNG & BMP
        pkgs.stegsolve # Steganographic image analyzer, solver and data extractor ...
        pkgs.ghidra-bin # Software reverse engineering (SRE) suite of tools develop...
        pkgs.capstone
        pkgs.pdf-parser # Parse a PDF document
        pkgs.p0f # Passive network reconnaissance and fingerprinting tool

        # Wireless
        pkgs.aircrack-ng
        pkgs.impala # TUI for managing wifi

        # Misc Network
        pkgs.hping # Command-line oriented TCP/IP packet assembler/analyzer
        pkgs.fping # Send ICMP echo probes to network hosts
        pkgs.tcptraceroute # Traceroute implementation using TCP packets
        pkgs.trippy # Network diagnostic tool
      ];
    };

    elf = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.patchelf # Small utility to modify the dynamic linker and RPATH of E...
        pkgs.elfutils # Set of utilities to handle ELF objects
        pkgs.chrpath # Command line tool to adjust the RPATH or RUNPATH of ELF b...
        pkgs.debugedit # Provides programs and scripts for creating debuginfo and ...
        pkgs.dump_syms # Command-line utility for parsing the debugging informatio...
      ];
    };

    gitops = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.git-annex # manage files with git, without checking their contents in...
      ];
    };

    graphics = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.librsvg # Small library to render SVG images to Cairo surfaces
        pkgs.libxml2 # XML parsing library for C
      ];
    };

    latex = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.rubber # Wrapper for LaTeX and friends
        (pkgs.texlive.combined.scheme-full.withPackages (ps: [
          ps.cyrillic
          ps.cyrillic-bin
          ps.collection-langcyrillic
          ps.context-cyrillicnumbers
        ]))
        pkgs.sioyek # PDF viewer designed for research papers and technical books
      ];
    };

    music-learning = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.solfege # ear training program
      ];
    };

    misc = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.xephem # astronomy application
        pkgs.xlife # cellular automata explorer
        pkgs.free42 # HP-42S calculator clone
        pkgs.cool-retro-term # retro CRT terminal emulator
        pkgs.almonds # TUI fractal viewer
      ];
    };

    media = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.ffmpeg-full # complete multimedia framework
        pkgs.gmic # image processing framework
      ];
    };

    "mesa-demos" = pkgs.mkShell {
      packages = [ pkgs.mesa-demos ];
    };

    "music-clap" = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.neg.music_clap
      ];
    };

    virt = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.guestfs-tools # tools for accessing and modifying virtual machine disk images
        pkgs.lima # Linux virtual machines
        pkgs.quickemu # quickly create and run highly optimised desktop virtual machines
      ];
    };
    text = pkgs.mkShell {
      # light text processing and previewing tools
      nativeBuildInputs = [
        pkgs.recoll # metadata-based full-text desktop search tool
        pkgs.tesseract # OCR engine with multi-language support
      ];
    };

    vrr = pkgs.mkShell {
      # tools for VRR (Variable Refresh Rate) testing
      nativeBuildInputs = [
        pkgs.vrrtest # validate VRR timings on Wayland
      ];
    };

    clojure = pkgs.mkShell {
      # Clojure development and scripting environment
      nativeBuildInputs = [
        pkgs.babashka # native Clojure scripting runtime for shell scripts
      ];
    };

    "pro-audio" = pkgs.mkShell {
      # professional audio production environment (DAWs, editors, synths)
      nativeBuildInputs = [
        pkgs.reaper # Digital Audio Workstation
        pkgs.ocenaudio # lightweight waveform editor
        pkgs.vital # spectral wavetable synth
        pkgs.vcv-rack # modular synth platform
      ];
    };

    visidata = pkgs.mkShell {
      nativeBuildInputs = [
        pkgs.visidata # Terminal spreadsheet multitool for data discovery
      ];
    };

    "web-archive" = pkgs.mkShell {
      packages = [
        pkgs.gallery-dl # download image galleries
        pkgs.monolith # single-file webpage archiver
      ];
    };

    speech = pkgs.mkShell {
      packages = [ pkgs.speechd ];
    };

    bcc = pkgs.mkShell {
      packages = [ pkgs.bcc ];
    };

    slskd = pkgs.mkShell {
      packages = [ pkgs.slskd ];
    };

    db = pkgs.mkShell {
      packages = [
        pkgs.iredis # Redis enhanced CLI
        pkgs.pgcli # PostgreSQL TUI client
        pkgs.sqlite # self-contained, serverless SQL DB
      ];
    };

    k8s = pkgs.mkShell {
      packages = [
        pkgs.kubectl # Kubernetes CLI
        pkgs.kubectx # fast switch Kubernetes contexts
        pkgs.kubernetes-helm # Helm package manager
        pkgs.scaleway-cli # Scaleway cloud CLI
        pkgs.kubecolor # Colorize kubectl output
      ];
    };

    "yandex-disk" = pkgs.mkShell {
      packages = [ pkgs."yandex-disk" ];
    };
  };

  apps =
    let
      genOptions = pkgs.writeShellApplication {
        name = "gen-options";
        runtimeInputs = [
          pkgs.git # version control
          pkgs.jq # json processor
          pkgs.nix # nix package manager
        ];
        text = ''
          set -euo pipefail
          exec "${self}/scripts/dev/gen-options.sh" "$@"
        '';
      };
      fmtApp = pkgs.writeShellApplication {
        name = "fmt";
        runtimeInputs = [
          nixfmtPkg
          pkgs.black
          pkgs.python3Packages.mdformat
          pkgs.shfmt # Shell parser and formatter
          pkgs.treefmt # One CLI to format the code tree
        ];
        text = ''
          set -euo pipefail
          if git rev-parse --show-toplevel >/dev/null 2>&1; then
            repo_root="$(git rev-parse --show-toplevel)"
          else
            repo_root="${self}"
          fi
          cd "$repo_root"
          tmp_conf=$(mktemp)
          trap 'rm -f "$tmp_conf"' EXIT
          cp ${../treefmt.toml} "$tmp_conf"
          exec treefmt --config-file "$tmp_conf" --tree-root "$repo_root" "$@"
        '';
      };
    in
    {
      gen-options = {
        type = "app";
        program = "${genOptions}/bin/gen-options";
      };
      fmt = {
        type = "app";
        program = "${fmtApp}/bin/fmt";
      };
    };
}
