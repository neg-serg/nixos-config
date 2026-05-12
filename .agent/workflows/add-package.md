______________________________________________________________________

## description: Add a new package to the configuration

# Add Package

## Steps

1. **Find the right module**:

   - CLI tools → `modules/cli/`
   - GUI apps → `modules/user/nix-maid/apps/`
   - Dev tools → `modules/dev/`
   - Media → `modules/media/`

1. **Add package with comment**:

   ```nix
   environment.systemPackages = [
     pkgs.my-package  # description of what it does
   ];
   ```

1. **Or for user packages**:

   ```nix
   users.users.neg.packages = [
     pkgs.my-package  # description
   ];
   ```

1. **Rebuild**:

   ```bash
   sudo nixos-rebuild switch --flake .#telfir
   ```

## Best Practices

- Always add inline comment
- Group related packages
- Use explicit `pkgs.package` instead of `with pkgs;`

## Finding Packages

```bash
nix search nixpkgs#package-name
```

Or visit: https://search.nixos.org/packages
