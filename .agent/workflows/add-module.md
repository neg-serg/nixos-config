______________________________________________________________________

## description: Create a new NixOS module

# Add Module

## Steps

1. **Create module directory**:

   ```bash
   mkdir -p modules/my-domain/
   ```

1. **Create main module file**:

   ```nix
   # modules/my-domain/default.nix
   { pkgs, lib, config, ... }: {
     imports = [ ./modules.nix ];
   }
   ```

1. **Create modules.nix**:

   ```nix
   # modules/my-domain/modules.nix
   { pkgs, lib, config, ... }: {
     # Your configuration here
     environment.systemPackages = [
       pkgs.some-package  # description
     ];
   }
   ```

1. **Create README.md**:

   ```markdown
   # My Domain Module

   Description in English.

   ## Includes
   - Feature 1
   - Feature 2
   ```

1. **Add to imports**: Edit the appropriate role or profile to import your module.

## Module Structure

```
modules/my-domain/
├── default.nix      # Entry point
├── modules.nix      # Main configuration
├── pkgs.nix         # Package lists (optional)
└── README.md        # Documentation
```

## Naming Conventions

- Lowercase directory names
- Use hyphens for multi-word names
- `modules.nix` for submodule imports
