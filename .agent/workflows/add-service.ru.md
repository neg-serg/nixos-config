______________________________________________________________________

## description: Добавление нового systemd сервиса

# Добавление systemd сервиса

## Системный сервис

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

## Пользовательский сервис

Используя хелперы nix-maid:

```nix
config.lib.neg.systemdUser.mkUnitFromPresets {
  description = "My User Service";
  ExecStart = "${pkgs.my-package}/bin/my-binary";
}
```

## Сервис таймера

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

## Управление

```bash
# Запустить
sudo systemctl start my-service

# Включить автозапуск
sudo systemctl enable my-service

# Логи
journalctl -u my-service -f
```

## Пользовательские сервисы

```bash
systemctl --user start my-service
systemctl --user status my-service
journalctl --user -u my-service
```
