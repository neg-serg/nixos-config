# LLM Module

Local LLM infrastructure with Ollama and Open WebUI.

## Structure

| File | Purpose |
|------|---------|
| `default.nix` | Main config with model paths |
| `ollama.nix` | Ollama service (ROCm) |
| `open-webui.nix` | Web interface |
| `codex-config.nix` | Codex assistant config |
| `pkgs.nix` | CLI tools |

## Configuration

Ollama with AMD ROCm on RX 7900 XTX:

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
ollama list              # List models
ollama pull codellama    # Download model
```
