# Secrets Module

Secret management with sops-nix.

## Structure

Encrypted secrets stored in `secrets/` and decrypted at build time.

## Usage

```nix
sops.secrets.my-secret = {
  sopsFile = ./secrets/file.yaml;
};
```
