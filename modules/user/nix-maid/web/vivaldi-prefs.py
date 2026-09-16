#!/usr/bin/env python3
"""Re-assert Vivaldi preferences at login.

Vivaldi rewrites Preferences from memory on exit, so this runs before the
browser starts (systemd user unit vivaldi-prefs in vivaldi.nix). The profile is
loaded once, only differing keys are touched, and the file is dumped back with
Vivaldi's own indent=1 formatting.
"""

import json
import os
import sys

PREFS = os.path.expanduser("~/.config/vivaldi/Default/Preferences")
NEG_THEME = "6265ce0d-0cec-40c1-8002-ef5c1f962c7a"


def load_prefs():
    if not os.path.isfile(PREFS):
        return None
    with open(PREFS) as f:
        return json.load(f)


def dump_prefs(p):
    with open(PREFS, "w") as f:
        json.dump(p, f, indent=1)


def vivaldi_actions(p):
    """vivaldi.actions[0], normalising the list/dict shapes Vivaldi uses."""
    acts = p.setdefault("vivaldi", {}).setdefault("actions", [{}])
    if isinstance(acts, list):
        if not acts:
            acts.append({})
        return acts[0]
    return acts


def main():
    p = load_prefs()
    if p is None:
        sys.exit(0)
    reports = []

    # 1a. Point the CSS mods dir at the profile mods folder so the compact
    # address-bar mod loads (the pref is empty by default).
    changed = False
    a = p.setdefault("vivaldi", {}).setdefault("appearance", {})
    css_dir = os.path.expanduser("~/.config/vivaldi/css-mods")
    if a.get("css_ui_mods_directory") != css_dir:
        a["css_ui_mods_directory"] = css_dir
        changed = True

    # Neg dark theme must stay selected; if it was dropped, the browser
    # chrome falls back to the default grey theme.
    th = p.setdefault("vivaldi", {}).setdefault("themes", {})
    if th.get("current") != NEG_THEME:
        th["current"] = NEG_THEME
        changed = True
    if th.get("current_private") != NEG_THEME:
        th["current_private"] = NEG_THEME
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
        reports.append(
            "css_ui_mods_directory, Neg theme, hidden panel bar and DevTools "
            "dark theme re-asserted"
        )

    # 1b. UI Auto-hide (Vivaldi 7.9+): toolbars slide out on hover — reads
    # as random popups. Force the master switch and per-toolbar flags off;
    # bars keep their manual visibility.
    ah = p.setdefault("vivaldi", {}).setdefault("auto_hide", {})
    auto_hide = {
        "enabled": False,  # master switch — off = no hover popups
        "panel": False,
        "tab_bar": False,
        "bookmarks_bar": False,
        "status_bar": False,
        "in_fullscreen": False,  # also off in fullscreen (address bar pops on hover otherwise)
    }
    changed = False
    for k, v in auto_hide.items():
        if ah.get(k) != v:
            ah[k] = v
            changed = True
    if changed:
        reports.append(f"UI Auto-hide disabled: {auto_hide}")

    act = vivaldi_actions(p)

    # 1c. Unbind Ctrl+W from close-tab so the emacs keys reach web pages
    # (dsh web composer/terminal; xterm forwards it to zsh as C-w).
    cmd = act.setdefault("COMMAND_CLOSE_TAB", {})
    shortcuts = cmd.get("shortcuts", [])
    if "ctrl+w" in shortcuts:
        cmd["shortcuts"] = [s for s in shortcuts if s != "ctrl+w"]
        reports.append(f"Ctrl+W unbound from close-tab: {cmd['shortcuts']}")

    # 1d. Bind Ctrl+G to close-tab. Vivaldi ships Ctrl+G as "Find Next in
    # Page", so the script frees that key; Ctrl+F4 keeps working too.
    changed = []
    shortcuts = cmd.get("shortcuts", [])
    if "ctrl+g" not in shortcuts:
        cmd["shortcuts"] = shortcuts + ["ctrl+g"]
        changed.append("close-tab=" + ",".join(cmd["shortcuts"]))
    find_next = act.get("COMMAND_FIND_NEXT_IN_PAGE")
    if isinstance(find_next, dict):
        shortcuts = find_next.get("shortcuts", [])
        if "ctrl+g" in shortcuts:
            find_next["shortcuts"] = [s for s in shortcuts if s != "ctrl+g"]
            changed.append("find-next=" + ",".join(find_next["shortcuts"]))
    if changed:
        reports.append("Ctrl+G closes the tab: " + "; ".join(changed))

    if reports:
        dump_prefs(p)
        print("\n".join(reports))


if __name__ == "__main__":
    main()
