import json, os, sys

prefs = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
if not os.path.isfile(prefs):
    sys.exit(0)
with open(prefs) as f:
    p = json.load(f)
acts = p.setdefault("vivaldi", {}).setdefault("actions", [{}])
if isinstance(acts, list):
    if not acts:
        acts.append({})
    act = acts[0]
else:
    act = acts
close_tab = act.setdefault("COMMAND_CLOSE_TAB", {})
shortcuts = close_tab.get("shortcuts", [])
if "ctrl+w" in shortcuts:
    close_tab["shortcuts"] = [s for s in shortcuts if s != "ctrl+w"]
    with open(prefs, "w") as f:
        json.dump(p, f, indent=1)
    print("Ctrl+W unbound from close-tab:", close_tab["shortcuts"])
