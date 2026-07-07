______________________________________________________________________

## name: sops description: SOPS-encrypted secrets management for NixOS. Use when creating, editing, or viewing encrypted secrets.

# SOPS Secrets

Secrets are stored encrypted in `secrets/` using SOPS (sops-nix).

## Commands

```bash
# Edit an existing secret
sops secrets/my-secret.sops.yaml

# Create a new secret
sops secrets/my-new-secret.sops.yaml

# Decrypt to stdout (for scripts)
sops -d secrets/my-secret.sops.yaml

# Rotate encryption keys
sops updatekeys secrets/my-secret.sops.yaml
```

## Adding a New Secret

1. Create the encrypted file:

   ```bash
   sops secrets/new-secret.sops.yaml
   ```

1. Reference it in NixOS config:

   ```nix
   sops.secrets."new-secret" = {
     sopsFile = ./secrets/new-secret.sops.yaml;
     owner = "some-user";
     mode = "0400";
   };
   ```

1. Use it in config or services:

   ```nix
   config.sops.secrets."new-secret".path
   ```

## Key Structure

Keys are stored in `.sops.yaml` at repo root. Age keys are used for encryption.
