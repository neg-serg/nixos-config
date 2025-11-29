# Документация

Актуальное русскоязычное руководство находится в `docs/manual/manual.ru.md`. В нём собраны как
системные модули, так и оставшийся Home Manager под `home/`, так что инструкции и заметки агента
теперь в одном месте.

Дополнительно во flake доступен пакет `antigravity` — Google Antigravity (agentic IDE). Требует
unfree Chrome. Запуск из корня:

```bash
NIXPKGS_ALLOW_UNFREE=1 nix run .#antigravity
```
