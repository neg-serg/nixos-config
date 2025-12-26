---
description: Add secrets with sops-nix / Добавление секретов через sops-nix
---

# Add Secret / Добавление секрета

## Prerequisites / Предварительные требования

Ensure you have age key configured / Убедитесь, что age ключ настроен:
```bash
cat ~/.config/sops/age/keys.txt
```

## Steps / Шаги

### 1. Create or edit secrets file / Создать или изменить файл секретов:
```bash
sops secrets/my-secrets.yaml
```

### 2. Add secret entry / Добавить секрет:
```yaml
my_secret: "secret-value-here"
api_key: "your-api-key"
```

### 3. Reference in Nix / Использовать в Nix:
```nix
sops.secrets.my_secret = {
  sopsFile = ./secrets/my-secrets.yaml;
  owner = "neg";
  mode = "0400";
};
```

### 4. Access in service / Доступ в сервисе:
```nix
environment.MY_SECRET_FILE = config.sops.secrets.my_secret.path;
```

## Decrypt in Shell / Расшифровка в шелле

```bash
sops -d secrets/my-secrets.yaml
```

## Re-encrypt / Перешифрование

After adding new keys / После добавления новых ключей:
```bash
sops updatekeys secrets/my-secrets.yaml
```

## Common Secret Types / Частые типы секретов

| Type / Тип | Usage / Использование |
|------------|----------------------|
| API keys | External services |
| Passwords | Database, services |
| SSH keys | Git, automation |
| Certificates | TLS, VPN |
