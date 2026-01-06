---
description: Добавление секретов через sops-nix
---

# Добавление секрета

## Предварительные требования

Убедитесь, что age ключ настроен:

```bash
cat ~/.config/sops/age/keys.txt
```

## Шаги

### 1. Создать или изменить файл секретов:

```bash
sops secrets/my-secrets.yaml
```

### 2. Добавить секрет:

```yaml
my_secret: "secret-value-here"
api_key: "your-api-key"
```

### 3. Использовать в Nix:

```nix
sops.secrets.my_secret = {
  sopsFile = ./secrets/my-secrets.yaml;
  owner = "neg";
  mode = "0400";
};
```

### 4. Доступ в сервисе:

```nix
environment.MY_SECRET_FILE = config.sops.secrets.my_secret.path;
```

## Расшифровка в шелле

```bash
sops -d secrets/my-secrets.yaml
```

## Перешифрование

После добавления новых ключей:

```bash
sops updatekeys secrets/my-secrets.yaml
```

## Частые типы секретов

| Тип | Использование |
|-----|---------------|
| API keys | External services |
| Passwords | Database, services |
| SSH keys | Git, automation |
| Certificates | TLS, VPN |
