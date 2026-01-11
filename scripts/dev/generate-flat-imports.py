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
            
            # Check if default.nix is pure aggregator
            if file == "default.nix":
                with open(filepath, 'r') as f:
                    content = f.read()
                
                # Remove comments
                content_nocomm = re.sub(r'#.*', '', content)
                
                # Check for indicators of content
                has_content = False
                
                # Keywords that imply logic/config
                start_indicators = [
                    "options", "config", "mkIf", "mkMerge", "mkOption", 
                    "services", "programs", "environment", "networking", "boot", 
                    "security", "users", "home", "fonts", "hardware", "virtualisation",
                    "nixpkgs", "nix", "system", "specialisation", "age"
                ]
                
                # If any indicator is set (assigned) or used
                # We check for "keyword =" or "keyword."
                
                for key in start_indicators:
                    if re.search(fr'\b{key}\b', content_nocomm):
                        has_content = True
                        break
                
                # Common shorthand: "foo.enable = true"
                if re.search(r'\.[a-zA-Z0-9_]+\s*=', content_nocomm):
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
