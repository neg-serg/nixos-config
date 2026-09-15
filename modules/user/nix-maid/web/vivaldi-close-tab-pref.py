import json
import os
import sys

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

changed = []

# Ctrl+W is unbound from close-tab elsewhere (emacs keys must reach web pages),
# which left the command on Ctrl+F4 alone; add Ctrl+G as the second binding.
close_tab = act.setdefault("COMMAND_CLOSE_TAB", {})
shortcuts = close_tab.get("shortcuts", [])
if "ctrl+g" not in shortcuts:
    close_tab["shortcuts"] = shortcuts + ["ctrl+g"]
    changed.append("close-tab=" + ",".join(close_tab["shortcuts"]))

# Vivaldi ships Ctrl+G as "Find Next in Page"; free the key so the binding
# above is the only one (F3 stays bound to that command).
find_next = act.get("COMMAND_FIND_NEXT_IN_PAGE")
if isinstance(find_next, dict):
    shortcuts = find_next.get("shortcuts", [])
    if "ctrl+g" in shortcuts:
        find_next["shortcuts"] = [s for s in shortcuts if s != "ctrl+g"]
        changed.append("find-next=" + ",".join(find_next["shortcuts"]))

if changed:
    with open(prefs, "w") as f:
        json.dump(p, f, indent=1)
    print("Ctrl+G closes the tab:", "; ".join(changed))
