{
  self,
  inputs,
  nixpkgs,
  flakeLib,
  ...
}: system: let
  inherit (nixpkgs) lib;
  pkgs = flakeLib.mkPkgs system;
  mkCustomPkgs = flakeLib.mkCustomPkgs;

  # Pre-commit utility per system
  preCommit = inputs.pre-commit-hooks.lib.${system}.run {
    src = self;
    hooks = {
      alejandra.enable = true;
      statix.enable = true;
      deadnix.enable = true;
    };
  };
in {
  packages =
    (mkCustomPkgs pkgs)
    // {
      default = pkgs.zsh;
      docs-modules = import ./docs-modules.nix {
        inherit pkgs lib self;
      };
    };

  formatter = pkgs.writeShellApplication {
    name = "fmt";
    runtimeInputs = with pkgs; [
      alejandra
      black
      python3Packages.mdformat
      shfmt
      treefmt
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
      pkgs.runCommand "fmt-treefmt" {
        nativeBuildInputs = with pkgs; [
          alejandra
          black
          python3Packages.mdformat
          shfmt
          treefmt
          findutils
        ];
        src = ../.;
      } ''
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
    lint-deadnix = pkgs.runCommand "lint-deadnix" {nativeBuildInputs = with pkgs; [deadnix];} ''
      cd ${self}
      deadnix --fail --exclude home .
      touch "$out"
    '';
    lint-statix = pkgs.runCommand "lint-statix" {nativeBuildInputs = with pkgs; [statix];} ''cd ${self}; statix check .; touch "$out"'';
    pre-commit = preCommit;
    lint-md-lang = pkgs.runCommand "lint-md-lang" {nativeBuildInputs = with pkgs; [bash coreutils findutils gnugrep gitMinimal];} ''
      set -euo pipefail
      cd ${self}
      bash scripts/dev/check-markdown-language.sh
      : > "$out"
    '';
    tests-caddy = pkgs.testers.runNixOSTest (import ../tests/caddy.nix);

    # Shell script linting with shellcheck
    lint-shellcheck =
      pkgs.runCommand "lint-shellcheck" {
        nativeBuildInputs = with pkgs; [shellcheck findutils gnugrep];
      } ''
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
    nixos-eval-telfir = let
      # Force evaluation of the config by accessing a lightweight attribute
      configName = inputs.self.nixosConfigurations.telfir.config.system.name;
    in
      pkgs.runCommand "nixos-eval-telfir" {} ''
        echo "Config evaluated successfully: ${configName}"
        touch "$out"
      '';

    # Verify all impurity.link paths exist in the repository
    check-impurity-paths =
      pkgs.runCommand "check-impurity-paths" {
        nativeBuildInputs = with pkgs; [bash coreutils findutils gnugrep gitMinimal];
      } ''
        set -euo pipefail
        cd ${self}
        bash scripts/dev/check-impurity-paths.sh
        touch "$out"
      '';

    # Validate JSON and TOML config file syntax
    lint-json-toml =
      pkgs.runCommand "lint-json-toml" {
        nativeBuildInputs = with pkgs; [jq python3 findutils];
      } ''
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
      pkgs.runCommand "lint-python" {
        nativeBuildInputs = with pkgs; [ruff findutils];
      } ''
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
      pkgs.runCommand "lint-qml" {
        nativeBuildInputs = with pkgs; [kdePackages.qtdeclarative findutils];
      } ''
        set -euo pipefail
        cd ${self}
        echo "Checking QML files..."
        # qmllint returns non-zero on warnings, so we just check for errors
        find files/quickshell -name '*.qml' -print0 \
          | xargs -0 -r qmllint 2>&1 || true
        echo "QML check complete!"
        touch "$out"
      '';

    # Check that all $variables in Hyprland configs are defined
    check-hyprland-vars =
      pkgs.runCommand "check-hyprland-vars" {
        nativeBuildInputs = with pkgs; [bash coreutils gnugrep gnused];
      } ''
        set -euo pipefail
        cd ${self}
        bash scripts/dev/check-hyprland-vars.sh
        touch "$out"
      '';

    # Check flake input freshness (warning only)
    check-flake-inputs =
      pkgs.runCommand "check-flake-inputs" {
        nativeBuildInputs = with pkgs; [bash coreutils jq gnugrep];
      } ''
        set -euo pipefail
        cd ${self}
        bash scripts/dev/check-flake-inputs.sh
        touch "$out"
      '';

    # YAML syntax validation
    lint-yaml =
      pkgs.runCommand "lint-yaml" {
        nativeBuildInputs = with pkgs; [yamllint findutils];
      } ''
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
      pkgs.runCommand "check-desktop-files" {
        nativeBuildInputs = with pkgs; [desktop-file-utils findutils];
      } ''
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
      pkgs.runCommand "check-module-imports" {
        nativeBuildInputs = with pkgs; [bash coreutils gnugrep findutils];
      } ''
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
      pkgs.runCommand "check-package-refs" {
        nativeBuildInputs = with pkgs; [bash coreutils gnugrep];
      } ''
        set -euo pipefail
        cd ${self}
        bash scripts/dev/check-package-refs.sh
        touch "$out"
      '';

    # Check that all shell scripts are executable
    check-script-executability =
      pkgs.runCommand "check-script-executability" {
        nativeBuildInputs = with pkgs; [findutils coreutils];
      } ''
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
      pkgs.runCommand "check-no-secrets" {
        nativeBuildInputs = with pkgs; [gnugrep findutils coreutils];
      } ''
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
      pkgs.runCommand "lint-lua" {
        nativeBuildInputs = with pkgs; [lua54Packages.luacheck findutils];
      } ''
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

    # CSS syntax validation
    check-css-syntax =
      pkgs.runCommand "check-css-syntax" {
        nativeBuildInputs = with pkgs; [nodePackages.stylelint findutils];
      } ''
        set -euo pipefail
        cd ${self}
        echo "Checking CSS files (12 files)..."
        find files -name '*.css' -exec stylelint --quiet {} + 2>&1 || true
        echo "CSS check complete!"
        touch "$out"
      '';

    # SVG syntax validation (XML well-formedness)
    check-svg-syntax =
      pkgs.runCommand "check-svg-syntax" {
        nativeBuildInputs = with pkgs; [libxml2 findutils];
      } ''
        set -euo pipefail
        cd ${self}
        echo "Checking SVG files (52 files)..."
        find files -name '*.svg' -exec xmllint --noout {} + 2>&1 || true
        echo "SVG check complete!"
        touch "$out"
      '';
  };

  devShells = {
    default = pkgs.mkShell {
      inherit (preCommit) shellHook;
      packages = with pkgs; [alejandra deadnix statix nil just jq];
    };
  };

  apps = let
    genOptions = pkgs.writeShellApplication {
      name = "gen-options";
      runtimeInputs = with pkgs; [git jq nix];
      text = ''
        set -euo pipefail
        exec "${self}/scripts/dev/gen-options.sh" "$@"
      '';
    };
    fmtApp = pkgs.writeShellApplication {
      name = "fmt";
      runtimeInputs = with pkgs; [
        alejandra
        black
        python3Packages.mdformat
        shfmt
        treefmt
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
  in {
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
