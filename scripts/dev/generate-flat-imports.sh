#!/usr/bin/env bash
set -euo pipefail

# Output file
OUTPUT="modules/flat.nix"
echo "{ ... }:" > "$OUTPUT"
echo "{" >> "$OUTPUT"
echo "  imports = [" >> "$OUTPUT"

# Find all .nix files in modules/
find modules -name "*.nix" | sort | while read -r file; do
    basename=$(basename "$file")
    
    # Skip the output file itself if it exists (though we are creating it)
    if [[ "$file" == "$OUTPUT" ]]; then continue; fi
    # Skip default.nix in modules root to avoid recursion if we replace it later
    if [[ "$file" == "modules/default.nix" ]]; then continue; fi

    if [[ "$basename" == "default.nix" ]]; then
        # Check if it's a pure aggregator
        # We look for 'options', 'config', 'mkMerge', 'mkIf', or complex logic.
        # Simple heuristic: if it doesn't have 'options =' and 'config =' and is small?
        # Better: check contents.
        
        # If file only imports, it looks like:
        # { ... }: { imports = [ ... ]; }
        
        # We search for clues of logic.
        if grep -qE "options\s*=|config\s*=|mkOption|mkEnableOption|mkIf|mkMerge|pkgs\.|lib\." "$file"; then
            # Has logic, include it
            echo "    ./${file#modules/}" >> "$OUTPUT"
        else
            # Likely pure aggregator, skip valid children will be added separately
            # But wait, what if it imports files we DON'T find? (e.g. from inputs?) 
            # We assume all local modules are files.
            echo "    # Skipping aggregator: $file"
            continue
        fi
    else
        # Regular module file
        echo "    ./${file#modules/}" >> "$OUTPUT"
    fi
done

echo "  ];" >> "$OUTPUT"
echo "}" >> "$OUTPUT"

echo "Generated $OUTPUT"
