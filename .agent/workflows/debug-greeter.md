---
description: Debug greetd and login issues
---

# Debug Greeter

## Quick Diagnostic

```bash
debug-greeter
```

This script shows:

- greetd service status
- quickshell processes
- directory permissions
- recent logs

## Manual Checks

### 1. Service Status:

```bash
systemctl status greetd
```

### 2. Journal Logs:

```bash
journalctl -u greetd -n 50
```

### 3. Quickshell Processes:

```bash
pgrep -a quickshell
```

### 4. Socket Permissions:

```bash
ls -la /run/greetd/
```

## Common Issues

| Issue | Solution |
|-------|----------|
| AppArmor blocking | Check `aa-status`, add profile |
| Missing greeter.qml | Verify `files/quickshell/greeter/` |
| PAM errors | Check sessionVariables for special chars |
| Black screen | Check Hyprland logs |

## Restart Greeter

```bash
sudo systemctl restart greetd
```

## Switch to TTY

If greeter is broken:

```
Ctrl+Alt+F2  # Switch to TTY2
```
