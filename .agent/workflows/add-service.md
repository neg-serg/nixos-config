______________________________________________________________________

## description: Add new systemd service

# Add Systemd Service

## System Service

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

## User Service

Using nix-maid helpers:

```nix
config.lib.neg.systemdUser.mkUnitFromPresets {
  description = "My User Service";
  ExecStart = "${pkgs.my-package}/bin/my-binary";
}
```

## Timer Service

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

## Control

```bash
# Start
sudo systemctl start my-service

# Enable
sudo systemctl enable my-service

# Logs
journalctl -u my-service -f
```

## User Services

```bash
systemctl --user start my-service
systemctl --user status my-service
journalctl --user -u my-service
```
