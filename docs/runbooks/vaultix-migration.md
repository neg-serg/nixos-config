# Migrating Home-Manager Secrets to Vaultix

This note describes how to move an existing Home Manager setup (currently using only `sops-nix`) to
`vaultix`, mirroring the approach in `/home/neg/src/dotfiles`. The steps assume you ultimately
deploy the HM modules through a NixOS host, because `vaultix` exposes its integration as a NixOS
module plus a helper CLI.

## Why Vaultix

| Aspect | `sops-nix` only | `vaultix` + `sops-nix` | | --- | --- | --- | | Encryption format | Any
backend (Age/GPG) | Age only, matching NixOS secrets best practices | | Recipient scoping | Manual
per-secret | Central `vaultix.configure` block distributes to nodes and extra Age recipients | |
Host bootstrap | Manual copy/decrypt | `vaultix` CLI (`vault edit`, `vault renc`) re-encrypts per
host and ensures files land in the right path during evaluation | | Module availability |
Home-manager friendly | NixOS module (best used together with HM flakes) |

### Advantages

- **Single source of truth**: `vaultix.configure` knows every node and produces per-host files
  automatically.
- **Age public keys only**: no need to share private keys or manage different KMS backends.
- **Bootstrap flow**: `vault edit secret.age` opens the decrypted payload with your preferred editor
  and re-encrypts on save.
- **Good fit for declarative NixOS**: the module ensures secrets are present before services
  activate.

### Caveats

- Works best when your HM modules are imported from a NixOS configuration; pure
  `home-manager switch --flake` on non-NixOS cannot use `services.vaultix`.
- Adds another dependency and CLI to your workflow.
- Still requires you to keep `sops-nix` for user-level secrets unless you migrate everything to Age
  files managed by `vaultix`.

## Migration Algorithm

1. **Inventory existing secrets**

   - Export a list from `secrets/default.nix` and note their current paths, owners, and file modes.
   - Decide which secrets must be available during system activation (passwords, VPN keys, WireGuard
     keys, etc.).

1. **Add the `vaultix` flake input**

   ```nix
   inputs.vaultix.url = "github:milieuim/vaultix";
   ```

   Re-run `nix flake update` to lock it.

1. **Expose `vaultix` to NixOS / HM outputs**

   - If you already export NixOS systems, append the module:
     ```nix
     outputs = { self, nixpkgs, vaultix, ... }:
     {
       nixosConfigurations.host = nixpkgs.lib.nixosSystem {
         modules = [
           ./hosts/host
           vaultix.nixosModules.default
           # existing modules …
         ];
         specialArgs = { inherit self inputs; };
       };
     }
     ```
   - For stand-alone HM configs, forward `vaultix` through `extraSpecialArgs` so that user modules
     can reference the same options (this becomes useful if you reuse the HM modules inside NixOS
     later).

1. **Drop `vaultix.configure` near the flake root**

   ```nix
   vaultix = vaultix.configure {
     nodes = self.nixosConfigurations;
     identity = self + "/secrets/identities/master.pub";
     extraRecipients = [
       # Additional Age recipients (CI, recovery key, etc.)
     ];
     defaultSecretDirectory = "./secrets";
     cache = "./secrets/.cache";
     extraPackages = [ self.packages.x86_64-linux.age-plugin-openpgp-card ];
   };
   ```

   This block teaches `vaultix` where the Age identity lives and what host set to manage.

1. **Define per-secret metadata** Create `secrets/default.nix` with entries like:

   ```nix
   {
     config,
     ...
   }:
   let
     username = config.dots.user.username;
   in
   {
     vaultix.secrets = {
       rootPass = {
         file = ./common/root.age;
         owner = "root";
         group = "users";
       };
       userPass = {
         file = ./common/user.age;
         owner = username;
         group = "users";
       };
       # … more secrets
     };
     vaultix.beforeUserborn = [ "rootPass" "userPass" ];
   }
   ```

   Each entry links the Age-encrypted file to ownership metadata that NixOS will enforce during
   activation.

1. **Create/convert Age files**

   - For every legacy sops secret, run `sops -d file | vaultix renc new-secret.age` or decrypt
     manually and re-encrypt with `rage` / `age` using the `vault edit` helper.
   - Store the `.age` files in the `secrets/` tree referenced above.

1. **Update modules to reference `config.vaultix.secrets.<name>.path`** Replace manual paths such as
   `config.sops.secrets."github-netrc".path` with the corresponding `vaultix` attribute wherever the
   secret is required (systemd units, services, etc.).

1. **Test end-to-end**

   - Run `nix run .#vault edit secrets/common/root.age` to confirm editing works.
   - Rebuild the host (`sudo nixos-rebuild switch --flake .#host`).
   - Verify the files appear on disk with the expected owner/permissions (`ls -l /run/secrets` or
     custom paths).

1. **Gradually retire `sops-nix` where appropriate** You can keep `sops-nix` for user-only secrets
   (like `netrc`) until everything is migrated. Both systems can coexist during transition.

## Operational Tips

- Put the Age public keys of every maintainer under `secrets/identities/`. Commit only the public
  part; import private keys locally.
- Cache-heavy repos benefit from `vaultix`'s `cache` directory; keep it inside `.gitignore`.
- Consider automated CI hooks (`self.vaultix.app.${system}.edit`) so that editing a secret is
  possible without installing extra tools globally.
- Document which secrets must be available before `userborn` (user creation) via
  `vaultix.beforeUserborn`.

## Summary

Transitioning to `vaultix` requires wiring a new flake input, defining the `vaultix.configure`
block, and gradually re-encrypting existing payloads as Age files. The payoff is consistent host
scoping and easier bootstrap compared to sprinkling `sops` secrets manually across modules.
