______________________________________________________________________

## description: Debug greetd and login issues / Отладка greetd и проблем входа

# Debug Greeter / Отладка Greeter

## Quick Diagnostic / Быстрая диагностика

```bash
debug-greeter
```

This script shows / Этот скрипт показывает:

- greetd service status / статус сервиса greetd
- quickshell processes / процессы quickshell
- directory permissions / права доступа
- recent logs / последние логи

## Manual Checks / Ручные проверки

### 1. Service Status / Статус сервиса:

```bash
systemctl status greetd
```

### 2. Journal Logs / Логи журнала:

```bash
journalctl -u greetd -n 50
```

### 3. Quickshell Processes / Процессы Quickshell:

```bash
pgrep -a quickshell
```

### 4. Socket Permissions / Права сокета:

```bash
ls -la /run/greetd/
```

## Common Issues / Частые проблемы

| Issue / Проблема | Solution / Решение | |------------------|-------------------| | AppArmor
blocking | Check `aa-status`, add profile | | Missing greeter.qml | Verify
`files/quickshell/greeter/` | | PAM errors | Check sessionVariables for special chars | | Black
screen | Check Hyprland logs |

## Restart Greeter / Перезапуск Greeter

```bash
sudo systemctl restart greetd
```

## Switch to TTY / Переключиться на TTY

If greeter is broken / Если greeter сломан:

```
Ctrl+Alt+F2  # Switch to TTY2
```
