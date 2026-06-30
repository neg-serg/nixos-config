#!/usr/bin/env python3
"""Recover ProxyPilot free-provider config from gopass-backed provider data."""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.pretty import pretty


class SecretMissing(Exception):
    """Raised when a required gopass secret cannot be read."""


def load_provider_roster(path: Path) -> list[dict]:
    data = yaml.safe_load(path.read_text()) or {}
    result = []
    for provider in data.get("providers", []):
        result.append(
            {
                "name": provider["name"],
                "base_url": provider["base_url"],
                "gopass_key": provider.get("gopass_key", ""),
                "dummy_key": provider.get("dummy_key", ""),
                "models": [
                    {"name": model["name"], "alias": model["alias"]}
                    for model in provider.get("models", [])
                ],
            }
        )
    return result


def read_gopass_secret(path: str) -> str:
    result = subprocess.run(
        ["gopass", "show", "-o", path],
        capture_output=True,
        text=True,
        check=False,
    )
    value = result.stdout.strip()
    if result.returncode != 0 or not value:
        raise SecretMissing(path)
    return value


def build_provider_entries(providers: list[dict], secret_reader) -> list[dict]:
    entries = []
    for provider in providers:
        if provider["gopass_key"]:
            try:
                api_key = secret_reader(provider["gopass_key"])
            except SecretMissing:
                continue
        else:
            api_key = provider["dummy_key"]
        if not api_key:
            continue
        entries.append(
            {
                "name": provider["name"],
                "base-url": provider["base_url"],
                "api-key": api_key,
                "models": provider["models"],
            }
        )
    return entries


def run_check(providers: list[dict], secret_reader) -> int:
    rc = 0
    for provider in providers:
        if not provider["gopass_key"]:
            continue
        try:
            secret_reader(provider["gopass_key"])
            pretty.ok(f"{provider['name']} ({provider['gopass_key']})")
        except SecretMissing:
            pretty.fail(f"MISSING: {provider['name']} ({provider['gopass_key']})")
            rc = 1
    return rc


def render_openai_compatibility(entries: list[dict]) -> str:
    lines = ["openai-compatibility:"]
    for entry in entries:
        lines.append(f'  - name: "{entry["name"]}"')
        lines.append(f'    base-url: "{entry["base-url"]}"')
        lines.append("    api-key-entries:")
        lines.append(f'      - api-key: "{entry["api-key"]}"')
        lines.append("    models:")
        for model in entry["models"]:
            lines.append(f'      - name: "{model["name"]}"')
            lines.append(f'        alias: "{model["alias"]}"')
    return "\n".join(lines)


def write_openai_compatibility(config_path: Path, entries: list[dict]) -> None:
    if not config_path.is_file():
        raise FileNotFoundError(config_path)
    section = render_openai_compatibility(entries)
    text = config_path.read_text()
    lines = text.splitlines()
    out = []
    skipping = False
    inserted = False
    for line in lines:
        if line.startswith("openai-compatibility:"):
            skipping = True
            continue
        if skipping and line and not line.startswith(" "):
            out.append(section)
            inserted = True
            skipping = False
        if not skipping:
            out.append(line)
    if skipping:
        out.append(section)
        inserted = True
    if not inserted and "openai-compatibility:" not in text:
        payload_marker = "# ── Payload rules"
        if payload_marker in text:
            prefix, suffix = text.split(payload_marker, 1)
            rebuilt = prefix.rstrip() + "\n" + section + "\n" + payload_marker + suffix
            config_path.write_text(rebuilt)
            return
        out.append("")
        out.append(section)
    config_path.write_text("\n".join(out) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["check", "recover"], nargs="?", default="recover")
    parser.add_argument("--roster", type=Path, default=Path("states/data/free_providers.yaml"))
    parser.add_argument(
        "--config", type=Path, default=Path.home() / ".config/proxypilot/config.yaml"
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    providers = load_provider_roster(args.roster)
    if args.mode == "check":
        return run_check(providers, read_gopass_secret)
    entries = build_provider_entries(providers, read_gopass_secret)
    if not entries:
        pretty.fail("No provider entries resolved")
        return 1
    write_openai_compatibility(args.config, entries)
    pretty.ok(f"Recovered openai-compatibility in {pretty.filepath(str(args.config))}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
