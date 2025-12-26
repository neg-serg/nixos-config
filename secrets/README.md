# Secrets / Секреты

Encrypted secrets for the configuration.

Зашифрованные секреты для конфигурации.

## Documentation / Документация

- Vaultix migration guidance: `../docs/runbooks/vaultix-migration.md` (EN)
- Vaultix миграция: `../docs/runbooks/vaultix-migration.ru.md` (RU)

## Usage / Использование

```bash
sops secrets/my-secrets.yaml  # Edit secrets / Редактировать секреты
sops -d secrets/my-secrets.yaml  # Decrypt / Расшифровать
```
