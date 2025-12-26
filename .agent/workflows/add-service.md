---
description: Add new systemd service / Добавление нового systemd сервиса
---

# Add Systemd Service / Добавление systemd сервиса

## System Service / Системный сервис

```nix
systemd.services.my-service = {
  description = "My Custom Service";
  wantedBy = [ "multi-user.target" ];
  after = [ "network.target" ];
  
  serviceConfig = {
    Type = "simple";
    ExecStart = "${pkgs.my-package}/bin/my-binary";
    Restart = "on-failure";
    RestartSec = 5;
    User = "my-user";
    Group = "my-group";
  };
};
```

## User Service / Пользовательский сервис

Using nix-maid helpers / Используя хелперы nix-maid:
```nix
config.lib.neg.systemdUser.mkUnitFromPresets {
  description = "My User Service";
  ExecStart = "${pkgs.my-package}/bin/my-binary";
}
```

## Timer Service / Сервис таймера

```nix
systemd.timers.my-timer = {
  wantedBy = [ "timers.target" ];
  timerConfig = {
    OnCalendar = "daily";
    Persistent = true;
  };
};

systemd.services.my-timer = {
  serviceConfig.ExecStart = "${pkgs.script}/bin/script";
};
```

## Control / Управление

```bash
# Start / Запустить
sudo systemctl start my-service

# Enable / Включить автозапуск
sudo systemctl enable my-service

# Logs / Логи
journalctl -u my-service -f
```

## User Services / Пользовательские сервисы

```bash
systemctl --user start my-service
systemctl --user status my-service
journalctl --user -u my-service
```
