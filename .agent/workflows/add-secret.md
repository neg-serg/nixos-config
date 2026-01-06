______________________________________________________________________

## description: Add secrets with sops-nix

# Add Secret

## Prerequisites

Ensure you have age key configured:

```bash
cat ~/.config/sops/age/keys.txt
```

## Steps

### 1. Create or edit secrets file:

```bash
sops secrets/my-secrets.yaml
```

### 2. Add secret entry:

```yaml
my_secret: "secret-value-here"
api_key: "your-api-key"
```

### 3. Reference in Nix:

```nix
sops.secrets.my_secret = {
  sopsFile = ./secrets/my-secrets.yaml;
  owner = "neg";
  mode = "0400";
};
```

### 4. Access in service:

```nix
environment.MY_SECRET_FILE = config.sops.secrets.my_secret.path;
```

## Decrypt in Shell

```bash
sops -d secrets/my-secrets.yaml
```

## Re-encrypt

After adding new keys:

```bash
sops updatekeys secrets/my-secrets.yaml
```

## Common Secret Types

| Type | Usage | |------|-------| | API keys | External services | | Passwords | Database, services
| | SSH keys | Git, automation | | Certificates | TLS, VPN |
