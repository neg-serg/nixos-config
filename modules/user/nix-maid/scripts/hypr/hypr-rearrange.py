import glob
import json
import os
import re
import subprocess
import sys


def get_hyprctl_json(cmd_type):
    try:
        result = subprocess.run(
            ["hyprctl", "-j", cmd_type],
            capture_output=True,
            text=True,
            check=True,
        )
        return json.loads(result.stdout)
    except subprocess.CalledProcessError as e:
        print(f"Error running hyprctl -j {cmd_type}: {e}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(
            f"Error parsing JSON from hyprctl -j {cmd_type}: {e}",
            file=sys.stderr,
        )
        sys.exit(1)


def parse_config_file(path, visited=None):
    """
    Recursively parses a Hyprland config file for window rules.
    Returns a list of rules found.
    """
    if visited is None:
        visited = set()

    # Expand user, vars, resolve path
    path = os.path.expandvars(os.path.expanduser(path))
    if not os.path.isabs(path):
        # Fallback for relative paths - assume relative to ~/.config/hypr/
        path = os.path.join(os.path.expanduser("~/.config/hypr/"), path)

    # Glob expansion
    paths = glob.glob(path)
    rules = []

    for p in paths:
        real_p = os.path.realpath(p)
        if real_p in visited:
            continue
        visited.add(real_p)

        try:
            with open(real_p, "r", encoding="utf-8") as f:
                lines = f.readlines()
        except Exception as e:
            print(
                f"Warning: could not read config file {p}: {e}",
                file=sys.stderr,
            )
            continue

        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue

            # Handle source inclusion
            if line.startswith("source ="):
                try:
                    # source = path
                    src_path = line.split("=", 1)[1].strip()
                    rules.extend(parse_config_file(src_path, visited))
                except Exception:
                    pass
                continue

            # Parse window rules
            # windowrulev2 = workspace 2, class:^(firefox)$
            # windowrule = workspace 2, ^(firefox)$

            if not (line.startswith("windowrule") and "=" in line):
                continue

            parts = line.split("=", 1)
            rule_def = parts[1].strip()

            # Split action and condition
            if "," not in rule_def:
                continue

            # "workspace 2 silent, class:^(firefox)$"
            # Split on first comma only? No, standard split is by comma.
            # But regex can contain commas.
            # Hyprland parsing is tricky. windowrulev2 = ACTION, PATTERN

            # Let's try to find the comma separating action and pattern.
            # Usually the action doesn't contain commas
            # (e.g. "workspace 2", "float")
            # except maybe for complex position args.

            # windowrulev2 = workspace 2, class:^(.*)$
            # windowrule = workspace 2, ^(.*)$

            args = [a.strip() for a in rule_def.split(",")]
            if len(args) < 2:
                continue

            action = args[0]
            # Reconstruct the rest as pattern/condition because
            # split(",") might break regex
            # actually windowrulev2 takes specific args.
            # windowrulev2 = workspace 2, class:^...

            # simple check for workspace action
            if not action.startswith("workspace"):
                continue

            ws_part = action.split()
            if len(ws_part) < 2:
                continue

            # "workspace 2 silent" -> id="2"
            workspace_id = ws_part[1]
            if not workspace_id:
                continue

            # Now find the condition/pattern
            # For windowrule: "workspace 2, ^regex$"
            # For windowrulev2: "workspace 2, class:^regex$"

            # We used split(","), so args[1:] are the rest.
            # But simple join might not be perfect if regex had comma.
            # Let's rely on string manipulation from the first comma.

            first_comma_idx = rule_def.find(",")
            if first_comma_idx == -1:
                continue

            condition_part = rule_def[first_comma_idx + 1:].strip()

            # Normalize pattern/type
            rule_type = "class"
            # default for windowrule if no type specified (implies class)
            pattern = condition_part

            if line.startswith("windowrulev2"):
                # windowrulev2 MUST have a field selector
                # condition_part = "class:^(firefox)$"
                if condition_part.startswith("class:"):
                    rule_type = "class"
                    pattern = condition_part[6:]
                elif condition_part.startswith("title:"):
                    rule_type = "title"
                    pattern = condition_part[6:]
                elif condition_part.startswith("initialClass:"):
                    rule_type = "initialClass"
                    pattern = condition_part[13:]
                elif condition_part.startswith("initialTitle:"):
                    rule_type = "initialTitle"
                    pattern = condition_part[13:]
                else:
                    # Ignore other v2 rules that aren't class/title related
                    continue

            # Strip quotes if present?
            # Hyprland usually doesn't need them but users add them.
            # pattern = pattern.strip('"\'')

            if workspace_id and pattern:
                rules.append(
                    {
                        "ws": workspace_id,
                        "type": rule_type,
                        "pattern": pattern,
                    }
                )

    return rules


def get_config_rules():
    """
    Entry point to parse config rules.
    """
    # Start from main config
    main_conf = "~/.config/hypr/hyprland.conf"
    return parse_config_file(main_conf)


def match_rule(client, rules):
    """
    Finds the first matching rule for a client.
    Returns target workspace matching rule or None.
    """
    client_class = client.get("class", "")
    client_title = client.get("title", "")
    client_initial_class = client.get("initialClass", "")
    client_initial_title = client.get("initialTitle", "")

    for rule in rules:
        pattern = rule["pattern"]
        r_type = rule["type"]

        matched = False
        try:
            if r_type == "class":
                if re.search(pattern, client_class):
                    matched = True
            elif r_type == "title":
                if re.search(pattern, client_title):
                    matched = True
            elif r_type == "initialClass":
                if re.search(pattern, client_initial_class):
                    matched = True
            elif r_type == "initialTitle":
                if re.search(pattern, client_initial_title):
                    matched = True
        except re.error:
            # Invalid regex in rule, skip
            continue

        if matched:
            return rule["ws"]

    return None


def main():
    dry_run = "--dry-run" in sys.argv

    clients = get_hyprctl_json("clients")
    rules = get_config_rules()

    print(f"Found {len(clients)} clients and {len(rules)} workspace rules.")

    moves = []

    for client in clients:
        address = client["address"]
        current_ws_id = str(client["workspace"]["id"])
        current_ws_name = client["workspace"]["name"]

        # Skip special workspaces? (usually negative or huge numbers?
        # or named 'special:...')
        # Hyprland special workspaces usually have ID < 0 or specific names
        if client["workspace"]["id"] < 0:
            continue

        target_ws = match_rule(client, rules)

        if target_ws:
            # Check if already there
            # Target might be ID "1" or name "1" or "name:doc"
            # We strictly compare string representation if integer-like

            # Normalize target_ws: remove "name:" if present to match
            # against ID or name?
            # hyprctl dispatch movetoworkspace accepts "ID" or "name:X"

            # Simple check: if current IS the search target
            # Ideally we resolve target_ws to ID, but rule might specify name.
            # Let's assume mismatch -> move.

            # Filter out obvious "already there"
            # If target is "1" and current is "1" -> skip
            target_simple = target_ws
            if (
                target_simple != current_ws_id
                and target_simple != current_ws_name
            ):
                # Additional check: "name:web" vs "web"
                if (
                    target_simple.startswith("name:")
                    and target_simple[5:] == current_ws_name
                ):
                    continue

                print(
                    f"Match: {client['class']} ({client['title'][:20]}...) -> "
                    f"Rule target: {target_ws} (Current: {current_ws_name})"
                )
                moves.append((address, target_ws))

    if not moves:
        print("No windows need moving.")
        return

    print(f"\nMoving {len(moves)} windows...")

    batch_cmds = []
    for addr, ws in moves:
        # movetoworkspacesilent
        cmd = f"dispatch movetoworkspacesilent {ws},address:{addr}"
        batch_cmds.append(cmd)

        if dry_run:
            print(f"[DRY RUN] {cmd}")

    if not dry_run:
        # Execute batch
        # hyprctl --batch "dispatch ... ; dispatch ..."
        full_batch = " ; ".join(batch_cmds)
        try:
            subprocess.run(["hyprctl", "--batch", full_batch], check=True)
            print("Done.")
        except subprocess.CalledProcessError as e:
            print(f"Error executing moves: {e}")


if __name__ == "__main__":
    main()
