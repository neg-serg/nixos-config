#!/usr/bin/env python3
import os
import re

MODULES_DIR = "modules"
OUTPUT_FILE = "modules/flat.nix"


def main():
    files_to_include = []

    print("Scanning modules...")
    for root, dirs, files in os.walk(MODULES_DIR):
        for file in files:
            if not file.endswith(".nix"):
                continue

            filepath = os.path.join(root, file)
            if filepath == OUTPUT_FILE:
                continue
            if filepath == "modules/default.nix":
                continue

            # Use 'modules/' relative path for checking exclusion
            rel_path = os.path.relpath(filepath, MODULES_DIR)
            if rel_path.startswith("features-data/") or rel_path.startswith(
                "lib/"
            ):
                print(f"Skipping data/lib file: {filepath}")
                continue

            if rel_path in [
                "user/default.nix",
                "system/default.nix",
                "hardware/default.nix",
            ]:
                print(f"Force skipping known aggregator: {filepath}")
                continue

            # Check if default.nix is pure aggregator
            if file == "default.nix":
                with open(filepath, "r") as f:
                    content = f.read()

                # Remove comments
                content_nocomm = re.sub(r"#.*", "", content)

                # Check for indicators of content
                has_content = False

                # Keywords that imply logic/config
                # Using regex to ensure they are used as keys or functions

                # Function-like keywords (called directly)
                funcs = ["mkIf", "mkMerge", "mkOption", "mkEnableOption"]
                for func in funcs:
                    if re.search(rf"\b{func}\b", content_nocomm):
                        has_content = True
                        break

                if not has_content:
                    # Property-like keywords (assigned or sub-accessed: key = ... or key.foo ...)
                    # We expect them to be followed by . or = or whitespace then =
                    props = [
                        "options",
                        "config",
                        "services",
                        "programs",
                        "environment",
                        "networking",
                        "boot",
                        "security",
                        "users",
                        "home",
                        "fonts",
                        "hardware",
                        "virtualisation",
                        "nixpkgs",
                        "nix",
                        "system",
                        "specialisation",
                        "age",
                        "inputs",
                    ]

                    # Regex: \bKEY\s*[.=]
                    # This avoids "nix-maid" matching "nix"
                    regex_props = r"\b(" + "|".join(props) + r")\s*[.=]"
                    if re.search(regex_props, content_nocomm):
                        has_content = True

                # Common shorthand: "foo.enable = true" - looking for unexpected top-level assignments
                # (handled by above props usually, but let's keep generic check too if needed)
                # But generic check caused issues. Let's rely on props list for now.

                # Check for "top-level" simple assignments not in imports?
                # If we have "foo = bar;" where foo is not in "imports".
                # But difficult to parse without full parser.

                # Logic: If it has imports and NO props/funcs, it is aggregator.
                # If it has NO imports, it MUST be content.
                if "imports" not in content_nocomm:
                    has_content = True

                if has_content:
                    files_to_include.append(filepath)
                else:
                    # It might be pure imports. Confirm by checking if "imports" is present.
                    if "imports" in content_nocomm:
                        print(f"Skipping potential aggregator: {filepath}")
                    else:
                        # Empty file or something else? Include to be safe.
                        files_to_include.append(filepath)

            else:
                # Check if it looks like a package (derivation)
                # Heuristic: matches { stdenv, ... } or { fetch... } but NOT { config, options ... }
                with open(filepath, "r") as f:
                    content = f.read()

                # Simple arg parser (first few lines)
                header = content.split(":", 1)[0]
                if (
                    "stdenv" in header
                    or "fetchFrom" in header
                    or "buildGoModule" in header
                ):
                    if "config" not in header and "options" not in header:
                        print(f"Skipping potential package: {filepath}")
                        continue

                if (
                    "browsers-table.nix" in file
                    or file.endswith("lib.nix")
                    or file == "firefox-theme.nix"
                    or file == "packages.nix"
                    or file == "files.nix"
                ):
                    print(f"Skipping helper/lib/package file: {filepath}")
                    continue

                if "hyprland" in rel_path and file in [
                    "services.nix",
                    "environment.nix",
                    "workspaces.nix",
                    "scratchpads.nix",
                ]:
                    print(f"Skipping hyprland helper file: {filepath}")
                    continue

                if file.endswith("prefgroups.nix") or file.endswith(
                    ".data.nix"
                ):
                    print(f"Skipping prefgroups/data file: {filepath}")
                    continue

                files_to_include.append(filepath)

    files_to_include.sort()

    with open(OUTPUT_FILE, "w") as f:
        f.write("{ ... }:\n{\n  imports = [\n")
        for path in files_to_include:
            relpath = os.path.relpath(path, MODULES_DIR)
            f.write(f"    ./{relpath}\n")
        f.write("  ];\n}\n")

    print(f"Generated {OUTPUT_FILE} with {len(files_to_include)} files.")


if __name__ == "__main__":
    main()
