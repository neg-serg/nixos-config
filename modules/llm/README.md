# LLM Module

Local LLM infrastructure with Ollama and Open WebUI.

## Structure

| File | Purpose |
|------|---------|
| `default.nix` | Main config with model paths |
| `ollama.nix` | Ollama service (ROCm acceleration) |
| `open-webui.nix` | Web interface for Ollama |
| `codex-config.nix` | Codex assistant config |
| `pkgs.nix` | CLI tools |

## Configuration

Ollama runs with AMD ROCm acceleration on RX 7900 XTX:

```nix
services.ollama = {
  enable = true;
  acceleration = "rocm";
  rocmOverrideGfx = "11.0.0";  # Navi 31
  models = "/zero/llm/ollama-models";
};
```

## Ports

| Service | Port | Description |
|---------|------|-------------|
| Ollama | 11434 | API endpoint |

## Usage

```bash
ollama run llama3.2      # Run a model
ollama list              # List installed models
ollama pull codellama    # Download a model
```
