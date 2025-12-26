# Secrets Module / Модуль секретов

Secret management with sops-nix.

Управление секретами с помощью sops-nix.

## Structure / Структура

Encrypted secrets stored in `secrets/` and decrypted at build time.

Зашифрованные секреты хранятся в `secrets/` и расшифровываются при сборке.

## Usage / Использование

```nix
sops.secrets.my-secret = {
  sopsFile = ./secrets/file.yaml;
};
```
