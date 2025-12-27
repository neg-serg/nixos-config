# LLM Module / Модуль LLM

Local LLM infrastructure with Ollama and Open WebUI.

Локальная инфраструктура LLM с Ollama и Open WebUI.

## Structure / Структура

| File | Purpose / Назначение | |------|---------| | `default.nix` | Main config with model paths /
Пути моделей | | `ollama.nix` | Ollama service (ROCm) / Сервис Ollama | | `open-webui.nix` | Web
interface / Веб-интерфейс | | `codex-config.nix` | Codex assistant config | | `pkgs.nix` | CLI tools
/ Утилиты |

## Configuration / Конфигурация

Ollama with AMD ROCm on RX 7900 XTX:

```nix
services.ollama = {
  enable = true;
  acceleration = "rocm";
  rocmOverrideGfx = "11.0.0";  # Navi 31
  models = "/zero/llm/ollama-models";
};
```

## Ports / Порты

| Service | Port | Description / Описание | |---------|------|-------------| | Ollama | 11434 | API
endpoint |

## Usage / Использование

```bash
ollama run llama3.2      # Run a model / Запустить модель
ollama list              # List models / Список моделей
ollama pull codellama    # Download / Скачать модель
```
