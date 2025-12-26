# Flatpak Module

Flatpak integration for containerized applications.

## Configuration

```nix
services.flatpak.enable = true;
```

## Usage

```bash
flatpak install flathub org.example.App
flatpak run org.example.App
```
