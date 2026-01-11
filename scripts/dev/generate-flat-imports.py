#!/usr/bin/env python3
import os
import re

MODULES_DIR = "modules"
OUTPUT_FILE = "modules/flat.nix"

def is_pure_aggregator(filepath):
    """
    Returns True if the file ONLY contains imports and no other configuration/options.
    """
    try:
        with open(filepath, 'r') as f:
            content = f.read()
    except Exception as e:
        print(f"Error reading {filepath}: {e}")
        return False

    # Remove comments (simple hash comments)
    content = re.sub(r'#.*', '', content)
    
    # Analyze the keys used in the attribute set
    # This is a rough parser. 
    # If we find any key that is NOT 'imports' inside the body, it's not a pure aggregator.
    
    # Heuristic:
    # 1. If it contains "options", "config", "mkIf", "mkMerge", it's definitely mixed.
    if re.search(r'\b(options|config|mkIf|mkMerge|mkOption|mkEnableOption)\b', content):
        return False
        
    # 2. If it contains known module properties like "programs", "environment", "services", "system", "networking", "boot", "security", "users", "home", "fonts"
    # This is hard to cover exhaustively. 
    
    # Alternative Strategy:
    # A pure aggregator usually strictly looks like:
    # { ... }: { imports = [ ... ]; }
    # or
    # { imports = [ ... ]; }
    
    # Let's clean up whitespace strings
    clean = re.sub(r'\s+', ' ', content).strip()
    
    # If file content (after header removal) is substantially longer than just imports...?
    
    # Regex to find "key =" assignments.
    # Exclude "imports ="
    # Note: assignments can be "foo.bar =" or "foo ="
    matches = re.findall(r'([a-zA-Z0-9_"\.]+)\s*=', content)
    keys = set(m.strip() for m in matches)
    
    # We ignore argument defaults (e.g. { pkgs ? ... }: ) which look like assignments.
    # But usually are in the header.
    
    # Let's rely on a simpler check:
    # If we skipped it before, we printed "Skipping aggregator".
    # I want to be conservative: Include it if doubt.
    # PURE aggregators are usually very short.
    
    # Let's modify the rule:
    # ONLY skip if we are 100% sure.
    # If matches only contains "imports", it's pure (ignoring args).
    
    # Filter out common arg names if they appear in header?
    # This is getting complex for regex.
    
    # Let's revert to the bash script logic but EXTEND the keywords.
    # And specifically look for "pure" imports blocks.
    return False 

    # On second thought, let's keep it simple:
    # Inspect files manually? There are 300 modules.
    
    # Let's write a script that DUMPS the content of Skipped files from previous run?
    # No, let's just make a better heuristic.
    
    # If the file contains `imports = [ ... ]` AND nothing else significant.
    # We can try to match `{ ... }: { imports = [ ... ]; }` pattern.
    pass

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
            if rel_path.startswith("features-data/") or rel_path.startswith("lib/"):
                print(f"Skipping data/lib file: {filepath}")
                continue

            if rel_path in ["user/default.nix", "system/default.nix", "hardware/default.nix"]:
                print(f"Force skipping known aggregator: {filepath}")
                continue
            
            # Check if default.nix is pure aggregator
            if file == "default.nix":
                with open(filepath, 'r') as f:
                    content = f.read()
                
                # Remove comments
                content_nocomm = re.sub(r'#.*', '', content)
                
                # Check for indicators of content
                has_content = False
                
                # Keywords that imply logic/config
                # Using regex to ensure they are used as keys or functions
                
                # Function-like keywords (called directly)
                funcs = ["mkIf", "mkMerge", "mkOption", "mkEnableOption"]
                for func in funcs:
                    if re.search(fr'\b{func}\b', content_nocomm):
                         has_content = True
                         break
                
                if not has_content:
                    # Property-like keywords (assigned or sub-accessed: key = ... or key.foo ...)
                    # We expect them to be followed by . or = or whitespace then =
                    props = [
                        "options", "config", 
                        "services", "programs", "environment", "networking", "boot", 
                        "security", "users", "home", "fonts", "hardware", "virtualisation",
                        "nixpkgs", "nix", "system", "specialisation", "age", "inputs"
                    ]
                    
                    # Regex: \bKEY\s*[.=]
                    # This avoids "nix-maid" matching "nix"
                    regex_props = r'\b(' + '|'.join(props) + r')\s*[.=]'
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
                with open(filepath, 'r') as f:
                    content = f.read()
                
                # Simple arg parser (first few lines)
                header = content.split(":", 1)[0]
                if "stdenv" in header or "fetchFrom" in header or "buildGoModule" in header:
                    if "config" not in header and "options" not in header:
                         print(f"Skipping potential package: {filepath}")
                         continue
                
                if "browsers-table.nix" in file or file.endswith("lib.nix") or file == "firefox-theme.nix" or file == "packages.nix" or file == "files.nix":
                     print(f"Skipping helper/lib/package file: {filepath}")
                     continue
                
                if "hyprland" in rel_path and file in ["services.nix", "environment.nix", "workspaces.nix", "scratchpads.nix"]:
                     print(f"Skipping hyprland helper file: {filepath}")
                     continue

                if file.endswith("prefgroups.nix") or file.endswith(".data.nix"):
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
