______________________________________________________________________

## description: Отладка greetd и проблем входа

# Отладка Greeter

## Быстрая диагностика

```bash
debug-greeter
```

Этот скрипт показывает:

- статус сервиса greetd
- процессы quickshell
- права доступа
- последние логи

## Ручные проверки

### 1. Статус сервиса:

```bash
systemctl status greetd
```

### 2. Логи журнала:

```bash
journalctl -u greetd -n 50
```

### 3. Процессы Quickshell:

```bash
pgrep -a quickshell
```

### 4. Права сокета:

```bash
ls -la /run/greetd/
```

## Частые проблемы

| Проблема | Решение | |----------|---------| | AppArmor blocking | Проверьте `aa-status`, добавьте
профиль | | Missing greeter.qml | Проверьте `files/quickshell/greeter/` | | PAM errors | Проверьте
sessionVariables на спецсимволы | | Black screen | Проверьте логи Hyprland |

## Перезапуск Greeter

```bash
sudo systemctl restart greetd
```

## Переключиться на TTY

Если greeter сломан:

```
Ctrl+Alt+F2  # Switch to TTY2
```
