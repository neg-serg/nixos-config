import json, os, sys

prefs = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
if not os.path.isfile(prefs):
    sys.exit(0)
with open(prefs) as f:
    p = json.load(f)

neg_theme = "6265ce0d-0cec-40c1-8002-ef5c1f962c7a"
changed = False

a = p.setdefault("vivaldi", {}).setdefault("appearance", {})
target = os.path.expanduser("~/.config/vivaldi/css-mods")
if a.get("css_ui_mods_directory") != target:
    a["css_ui_mods_directory"] = target
    changed = True

# Neg dark theme must stay selected; if it was dropped, the browser
# chrome falls back to the default grey theme.
th = p.setdefault("vivaldi", {}).setdefault("themes", {})
if th.get("current") != neg_theme:
    th["current"] = neg_theme
    changed = True
if th.get("current_private") != neg_theme:
    th["current_private"] = neg_theme
    changed = True

# Hide the panel bar by default for new windows (was visible again
# after the pref reset).
wd = (
    p.setdefault("vivaldi", {})
    .setdefault("panels", {})
    .setdefault("window_defaults", {})
)
if wd.get("barVisible") is not False:
    wd["barVisible"] = False
    changed = True
if wd.get("contentVisible") is not False:
    wd["contentVisible"] = False
    changed = True

# DevTools UI theme: keep it dark like the browser chrome. The value
# inside devtools.preferences is a JSON-encoded string ("dark").
dt = p.setdefault("devtools", {}).setdefault("preferences", {})
if dt.get("uiTheme") != '"dark"':
    dt["uiTheme"] = '"dark"'
    changed = True

if changed:
    with open(prefs, "w") as f:
        json.dump(p, f, indent=1)
    print(
        "css_ui_mods_directory, Neg theme, hidden panel bar and DevTools dark theme re-asserted"
    )
