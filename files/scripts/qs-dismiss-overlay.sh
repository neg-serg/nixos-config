#!/usr/bin/env bash
# Dismiss all quickshell overlay windows by namespace pattern.
# Overlays use namespaces like: quickshell, qs-calendar, qs-monitor
# We close any window whose namespace starts with "qs-" or is "quickshell"
# but NOT the bar panels (qs-panel, qs-content-left, qs-content-right).

# Strategy: iterate hyprctl layers, find overlay surfaces, close them.
# Simpler: just toggle visibility via hyprctl keyword on WlrLayershell.
# But hyprctl doesn't directly close layershell surfaces.

# Alternative: write a trigger file that quickshell watches.
TRIGGER="$HOME/.cache/quickshell/dismiss-overlay"
mkdir -p "$(dirname "$TRIGGER")"
touch "$TRIGGER"
