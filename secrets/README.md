# Secrets

Encrypted secrets for the configuration.

## Documentation

- Vaultix migration guidance: `../docs/runbooks/vaultix-migration.md` (EN)
- Vaultix migration (RU): `../docs/runbooks/vaultix-migration.ru.md`

## Usage

```bash
sops secrets/my-secrets.yaml     # Edit secrets
sops -d secrets/my-secrets.yaml  # Decrypt
```
