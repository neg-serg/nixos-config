---
description: Создание пользовательского пакета / оверлея
---

# Добавление пакета

## Шаги

### 1. Создать директорию пакета:

```bash
mkdir -p packages/my-package
```

### 2. Написать деривацию:

```nix
# packages/my-package/default.nix
{ pkgs, lib, ... }:

pkgs.stdenv.mkDerivation {
  pname = "my-package";
  version = "1.0.0";
  
  src = pkgs.fetchFromGitHub {
    owner = "username";
    repo = "repo-name";
    rev = "v1.0.0";
    sha256 = lib.fakeSha256;
  };
  
  buildInputs = [ pkgs.some-dependency ];
  
  meta = with lib; {
    description = "My custom package";
    license = licenses.mit;
  };
}
```

### 3. Добавить в оверлей:

```nix
# packages/overlay.nix
final: prev: {
  my-package = final.callPackage ./my-package { };
}
```

### 4. Использовать в конфигурации:

```nix
environment.systemPackages = [ pkgs.my-package ];
```

## Пакеты-скрипты

Для простых скриптов:

```nix
pkgs.writeShellApplication {
  name = "my-script";
  runtimeInputs = [ pkgs.jq pkgs.curl ];
  text = ''
    #!/usr/bin/env bash
    echo "Hello, world!"
  '';
}
```

## Получение хеша

```bash
nix-prefetch-url --unpack https://github.com/user/repo/archive/v1.0.0.tar.gz
```
