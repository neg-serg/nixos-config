# Модуль LLM

Локальная инфраструктура LLM с Ollama и Open WebUI.

## Структура

| Файл | Назначение |
|------|------------|
| `default.nix` | Основной конфиг и пути моделей |
| `ollama.nix` | Сервис Ollama (ROCm) |
| `open-webui.nix` | Веб-интерфейс |
| `codex-config.nix` | Конфиг ассистента Codex |
| `pkgs.nix` | CLI утилиты |

## Конфигурация

Ollama с AMD ROCm на RX 7900 XTX:

```nix
services.ollama = {
  enable = true;
  acceleration = "rocm";
  rocmOverrideGfx = "11.0.0";  # Navi 31
  models = "/zero/llm/ollama-models";
};
```

## Порты

| Сервис | Порт | Описание |
|--------|------|----------|
| Ollama | 11434 | API endpoint |

## Использование

```bash
ollama run llama3.2      # Запустить модель
ollama list              # Список моделей
ollama pull codellama    # Скачать модель
```
