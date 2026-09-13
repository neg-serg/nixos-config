import json, os, sys

prefs = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
if not os.path.isfile(prefs):
    sys.exit(0)
with open(prefs) as f:
    p = json.load(f)
ah = p.setdefault("vivaldi", {}).setdefault("auto_hide", {})
target = {
    "enabled": False,  # master switch — off = no hover popups
    "panel": False,
    "tab_bar": False,
    "bookmarks_bar": False,
    "status_bar": False,
    "in_fullscreen": False,  # also off in fullscreen (address bar pops on hover otherwise)
}
changed = False
for k, v in target.items():
    if ah.get(k) != v:
        ah[k] = v
        changed = True
if changed:
    with open(prefs, "w") as f:
        json.dump(p, f, indent=1)
    print("UI Auto-hide disabled:", target)
