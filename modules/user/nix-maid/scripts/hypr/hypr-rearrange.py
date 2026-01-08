import json
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


def get_config_rules():
    """
    Parses `hyprctl rules` output to find workspace rules.
    Returns a list of (rule_type, rule_pattern, workspace_id) tuples.
    """
    rules = []
    try:
        # hyprctl rules returns text, not JSON
        result = subprocess.run(
            ["hyprctl", "rules"], capture_output=True, text=True, check=True
        )
        output = result.stdout

        # We are looking for lines like:
        # windowrulev2 = workspace 2, class:^(firefox)$
        # windowrule = workspace 2, ^(firefox)$

        # Regex for windowrulev2
        # Example: windowrule = workspace 2, class:^(firefox)$
        # Standard format from `hyprctl rules`:
        # rule: workspace 2, class:^(firefox)$

        # Let's inspect typical output format. It's usually a list of rules.
        # "windowrule: workspace 2, ^(firefox)$"
        # "windowrulev2: workspace 2, class:^(firefox)$"

        for line in output.splitlines():
            line = line.strip()
            if not line:
                continue

            workspace_id = None
            pattern = None
            rule_type = (
                None  # 'class', 'title', 'initialClass', 'initialTitle'
            )

            # Simple parsing strategy: look for "workspace" action
            if "workspace" in line:
                # Handle windowrulev2 format:
                # "windowrulev2: workspace 2 silent, class:^(firefox)$"
                # Handle windowrule format:
                # "windowrule: workspace 2, ^(firefox)$" -> implies class

                parts = line.split(":", 1)
                if len(parts) < 2:
                    continue

                rule_def = parts[
                    1
                ].strip()  # "workspace 2 silent, class:^(firefox)$"

                # Split action and condition
                if "," not in rule_def:
                    continue

                action_part, condition_part = rule_def.split(",", 1)
                action_part = action_part.strip()
                condition_part = condition_part.strip()

                # Check if action is workspace
                if action_part.startswith("workspace"):
                    # Extract ID: "workspace 2 silent" -> "2"
                    ws_args = action_part.split()
                    if len(ws_args) >= 2:
                        # Find the first numeric part or named workspace
                        # Usually "workspace ID" or "workspace name"
                        # Simple heuristics: take the second token
                        raw_ws = ws_args[1]
                        workspace_id = raw_ws.rstrip(",")

                if not workspace_id:
                    continue

                # Parse condition
                # class:^(firefox)$
                # title:^(.*)$
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
                    # windowrule (v1) implies class matched against
                    # regex if just regex
                    # "workspace 2, ^(firefox)$"
                    rule_type = "class"
                    pattern = condition_part

                if workspace_id and pattern:
                    rules.append(
                        {
                            "ws": workspace_id,
                            "type": rule_type,
                            "pattern": pattern,
                        }
                    )

    except Exception as e:
        print(f"Error getting rules: {e}", file=sys.stderr)

    return rules


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
