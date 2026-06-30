#!/usr/bin/env python3
"""DNS-based VPN split routing: observe, learn, and route domains through VPN/proxy."""

from __future__ import annotations

import argparse
import json
import shutil
import socket
import ssl
import subprocess
import sys
import time
from datetime import datetime, timedelta, timezone
from pathlib import Path

import yaml

sys.path.insert(0, str(Path(__file__).resolve().parent))
from lib.pretty import pretty

DEFAULT_CONFIG_PATH = Path.home() / ".config" / "vpn-split-router" / "config.yaml"
DEFAULT_STATE_PATH = Path.home() / ".local" / "state" / "vpn-split-router" / "state.json"
DEFAULT_OBSERVED_PATH = (
    Path.home() / ".local" / "state" / "vpn-split-router" / "observed-domains.txt"
)
DEFAULT_VPN_DOMAINS_PATH = Path.home() / ".local" / "state" / "vpn-split-router" / "vpn-domains.txt"
DEFAULT_RUNTIME_CONFIG_PATH = Path.home() / ".config" / "sing-box-tun" / "config.json"
DEFAULT_POLICY_PATH = Path.home() / ".config" / "vpn-split-router" / "policy.yaml"
DEFAULT_POLICY_ROLLBACK_PATH = Path.home() / ".config" / "vpn-split-router" / "policy.yaml.rollback"


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def now_iso() -> str:
    return now_utc().isoformat()


def parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    return datetime.fromisoformat(value)


def load_config(path: Path) -> dict:
    with open(path) as fh:
        payload = yaml.safe_load(fh.read()) or {}
    payload.setdefault("settings", {})
    payload.setdefault("seed_domains", [])
    return payload


def read_json(path: Path) -> dict:
    if not path.exists():
        return {"domains": {}}
    payload = json.loads(path.read_text(encoding="utf-8"))
    payload.setdefault("domains", {})
    return payload


def write_text_if_changed(path: Path, content: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.read_text(encoding="utf-8") == content:
        return False
    tmp_path = path.with_suffix(path.suffix + ".tmp")
    tmp_path.write_text(content, encoding="utf-8")
    tmp_path.replace(path)
    return True


def write_json(path: Path, payload: dict) -> bool:
    return write_text_if_changed(path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def ensure_record(domain: str, source: str, now_value: str) -> dict:
    return {
        "domain": domain,
        "source": source,
        "route": "probing",
        "reason": "new_candidate",
        "first_seen": now_value,
        "last_seen": now_value,
        "last_checked": None,
        "ttl_until": None,
        "success_count": 0,
        "failure_count": 0,
        "latency_ms": None,
        "confidence": "low",
    }


def read_observed_domains(path: Path) -> list[str]:
    if not path.exists():
        return []
    domains = []
    seen = set()
    for raw in path.read_text(encoding="utf-8").splitlines():
        domain = raw.strip().lower()
        if not domain or domain in seen:
            continue
        seen.add(domain)
        domains.append(domain)
    return domains


def clear_observed_domains(path: Path) -> bool:
    return write_text_if_changed(path, "")


def collect_candidates(config: dict, state: dict, observed: list[str], now_value: str) -> dict:
    domains = state.setdefault("domains", {})
    for domain in config.get("seed_domains", []):
        record = domains.setdefault(domain, ensure_record(domain, "seed", now_value))
        record["source"] = "seed"
        record["last_seen"] = now_value
    for domain in observed:
        record = domains.setdefault(domain, ensure_record(domain, "observed", now_value))
        record["last_seen"] = now_value
    return state


def prune_stale_observed_domains(state: dict, config: dict, now_value: str | None = None) -> None:
    current = parse_iso(now_value) if now_value else now_utc()
    stale_after = config.get("settings", {}).get("observed_stale_after_seconds")
    if not stale_after:
        return

    stale_before = current - timedelta(seconds=stale_after)
    stale_domains = []
    for domain, record in state.get("domains", {}).items():
        if record.get("source") != "observed":
            continue
        last_seen = parse_iso(record.get("last_seen"))
        if last_seen and last_seen < stale_before:
            stale_domains.append(domain)

    for domain in stale_domains:
        state["domains"].pop(domain, None)


def expire_routes(state: dict, now_iso: str | None = None) -> None:
    current = parse_iso(now_iso) if now_iso else now_utc()
    for record in state.get("domains", {}).values():
        ttl_until = parse_iso(record.get("ttl_until"))
        if ttl_until and ttl_until <= current:
            record["route"] = "probing"
            record["reason"] = "ttl_expired"


def apply_probe_result(record: dict, config: dict, probe: dict) -> dict:
    settings = config["settings"]
    source = record["source"]
    threshold = (
        settings["seed_vpn_failure_threshold"]
        if source == "seed"
        else settings["observed_vpn_failure_threshold"]
    )

    record["last_checked"] = now_iso()
    record["latency_ms"] = probe.get("latency_ms")

    if probe["status"] == "ok":
        record["success_count"] += 1
        record["failure_count"] = 0
        record["route"] = "direct"
        record["reason"] = "probe_ok"
        record["ttl_until"] = (
            now_utc() + timedelta(seconds=settings["direct_ttl_seconds"])
        ).isoformat()
        record["confidence"] = "high"
        return record

    record["failure_count"] += 1
    record["success_count"] = 0
    record["reason"] = f"probe_{probe['status']}"
    if record["failure_count"] >= threshold:
        record["route"] = "vpn"
        record["ttl_until"] = (
            now_utc() + timedelta(seconds=settings["vpn_ttl_seconds"])
        ).isoformat()
        record["confidence"] = "high" if source == "seed" else "medium"
    else:
        record["route"] = "probing"
        record["confidence"] = "low"
    return record


def resolve_vpn_outbound(payload: dict) -> str:
    outbounds = payload.get("outbounds", [])
    for outbound in outbounds:
        tag = outbound.get("tag")
        if outbound.get("type") == "wireguard" and tag:
            return tag
    for outbound in outbounds:
        tag = outbound.get("tag")
        if tag and "vpn" in tag.lower():
            return tag
    return "vpn"


def load_policy(path: Path) -> dict:
    if not path.exists():
        return {"always_direct": {"domains": []}, "always_vpn": {"domains": []}}
    payload = yaml.safe_load(path.read_text(encoding="utf-8")) or {}
    payload.setdefault("always_direct", {"domains": []})
    payload.setdefault("always_vpn", {"domains": []})
    payload["always_direct"].setdefault("domains", [])
    payload["always_vpn"].setdefault("domains", [])
    return payload


def save_policy(path: Path, policy: dict) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    content = yaml.safe_dump(policy, default_flow_style=False, sort_keys=False)
    return write_text_if_changed(path, content)


def policy_sync_to_routing(
    policy_path: Path,
    runtime_config_path: Path,
    probe_vpn_domains: list[str] | None = None,
) -> bool:
    if not runtime_config_path.exists():
        return False
    policy = load_policy(policy_path)
    payload = json.loads(runtime_config_path.read_text(encoding="utf-8"))
    route = payload.setdefault("route", {})

    managed_tags = {"vpn-policy-direct", "vpn-policy-vpn", "vpn-split-router-managed"}
    rules = [rule for rule in route.get("rules", []) if rule.get("tag") not in managed_tags]

    outbound_tag = resolve_vpn_outbound(payload)

    # Policy always-direct (highest priority)
    direct_domains = sorted(policy.get("always_direct", {}).get("domains", []))
    if direct_domains:
        rules.insert(
            0,
            {"tag": "vpn-policy-direct", "domain_suffix": direct_domains, "outbound": "direct"},
        )

    # Policy always-vpn
    vpn_domains = sorted(policy.get("always_vpn", {}).get("domains", []))
    if vpn_domains:
        rules.insert(
            0,
            {"tag": "vpn-policy-vpn", "domain_suffix": vpn_domains, "outbound": outbound_tag},
        )

    # Probe-based managed rules
    if probe_vpn_domains:
        rules.insert(
            0,
            {
                "tag": "vpn-split-router-managed",
                "domain_suffix": sorted(probe_vpn_domains),
                "outbound": outbound_tag,
            },
        )

    route["rules"] = rules
    return write_text_if_changed(
        runtime_config_path, json.dumps(payload, indent=2, sort_keys=True) + "\n"
    )


def sync_runtime_config(config_path: Path, vpn_domains: list[str]) -> bool:
    if not config_path.exists():
        return False
    payload = json.loads(config_path.read_text(encoding="utf-8"))
    route = payload.setdefault("route", {})
    managed_tags = {"vpn-policy-direct", "vpn-policy-vpn", "vpn-split-router-managed"}
    rules = [rule for rule in route.get("rules", []) if rule.get("tag") not in managed_tags]
    if vpn_domains:
        outbound_tag = resolve_vpn_outbound(payload)
        rules.insert(
            0,
            {
                "tag": "vpn-split-router-managed",
                "domain_suffix": vpn_domains,
                "outbound": outbound_tag,
            },
        )
    route["rules"] = rules
    return write_text_if_changed(config_path, json.dumps(payload, indent=2, sort_keys=True) + "\n")


def probe_domain(domain: str, timeout_seconds: float) -> dict:
    started = time.perf_counter()
    try:
        with socket.create_connection((domain, 443), timeout=timeout_seconds) as sock:
            context = ssl.create_default_context()
            with context.wrap_socket(sock, server_hostname=domain):
                latency_ms = int((time.perf_counter() - started) * 1000)
                return {"status": "ok", "latency_ms": latency_ms}
    except socket.timeout as exc:
        return {"status": "timeout", "latency_ms": None, "error": str(exc)}
    except ssl.SSLError as exc:
        return {"status": "tls_error", "latency_ms": None, "error": str(exc)}
    except OSError as exc:
        return {"status": "connect_error", "latency_ms": None, "error": str(exc)}


def current_vpn_domains(state: dict) -> list[str]:
    return sorted(
        domain
        for domain, record in state.get("domains", {}).items()
        if record.get("route") == "vpn"
    )


def refresh_outputs(
    state: dict,
    config: dict,
    observed_path: Path,
    vpn_domains_path: Path,
    runtime_config_path: Path,
    policy_path: Path | None = None,
    now_value: str | None = None,
) -> None:
    expire_routes(state, now_iso=now_value)
    prune_stale_observed_domains(state, config, now_value=now_value)
    vpn_domains = current_vpn_domains(state)
    observed = [
        domain
        for domain, record in sorted(state.get("domains", {}).items())
        if record.get("source") == "observed"
    ]
    write_text_if_changed(observed_path, "".join(f"{domain}\n" for domain in observed))
    write_text_if_changed(vpn_domains_path, "".join(f"{domain}\n" for domain in vpn_domains))
    sync_runtime_config(runtime_config_path, vpn_domains)
    if policy_path:
        policy_sync_to_routing(policy_path, runtime_config_path, probe_vpn_domains=vpn_domains)


def command_status(args: argparse.Namespace) -> int:
    state = read_json(args.state)
    expire_routes(state)
    domains = state.get("domains", {})
    payload = {
        "total": len(domains),
        "vpn": sum(1 for record in domains.values() if record.get("route") == "vpn"),
        "direct": sum(1 for record in domains.values() if record.get("route") == "direct"),
        "probing": sum(1 for record in domains.values() if record.get("route") == "probing"),
    }
    print(json.dumps(payload, indent=2, sort_keys=True))
    return 0


def command_list(args: argparse.Namespace) -> int:
    state = read_json(args.state)
    expire_routes(state)
    for domain in sorted(state.get("domains", {})):
        record = state["domains"][domain]
        print(f"{domain}\t{record.get('route', 'probing')}\t{record.get('reason', '')}")
    return 0


def command_recheck(args: argparse.Namespace) -> int:
    config_path = args.config
    state_path = args.state
    observed_path = args.observed
    vpn_domains_path = args.vpn_domains
    runtime_config_path = args.runtime_config

    config = load_config(config_path)
    state = read_json(state_path)
    observed = read_observed_domains(observed_path)
    state = collect_candidates(config, state, observed, now_iso())
    clear_observed_domains(observed_path)
    expire_routes(state)
    prune_stale_observed_domains(state, config)
    for record in state["domains"].values():
        probe = probe_domain(
            record["domain"], timeout_seconds=config["settings"]["probe_timeout_seconds"]
        )
        apply_probe_result(record, config, probe)
    write_json(state_path, state)
    refresh_outputs(
        state,
        config,
        observed_path,
        vpn_domains_path,
        runtime_config_path,
        policy_path=args.policy,
    )
    return 0


def command_forget(args: argparse.Namespace) -> int:
    state = read_json(args.state)
    for domain in args.domains:
        state.setdefault("domains", {}).pop(domain.lower(), None)
    write_json(args.state, state)
    config = load_config(args.config)
    refresh_outputs(
        state,
        config,
        args.observed,
        args.vpn_domains,
        args.runtime_config,
        policy_path=args.policy,
    )
    return 0


def command_mark_vpn(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    state = read_json(args.state)
    now_value = now_iso()
    ttl_seconds = config["settings"].get("vpn_ttl_seconds", 0)
    for domain in args.domains:
        normalized = domain.lower()
        record = state.setdefault("domains", {}).setdefault(
            normalized, ensure_record(normalized, "observed", now_value)
        )
        record["last_seen"] = now_value
        record["route"] = "vpn"
        record["reason"] = "manual_vpn"
        record["confidence"] = "high"
        record["ttl_until"] = (now_utc() + timedelta(seconds=ttl_seconds)).isoformat()
    write_json(args.state, state)
    refresh_outputs(
        state,
        config,
        args.observed,
        args.vpn_domains,
        args.runtime_config,
        policy_path=args.policy,
    )
    return 0


def command_mark_direct(args: argparse.Namespace) -> int:
    config = load_config(args.config)
    state = read_json(args.state)
    now_value = now_iso()
    ttl_seconds = config["settings"].get("direct_ttl_seconds", 0)
    for domain in args.domains:
        normalized = domain.lower()
        record = state.setdefault("domains", {}).setdefault(
            normalized, ensure_record(normalized, "observed", now_value)
        )
        record["last_seen"] = now_value
        record["route"] = "direct"
        record["reason"] = "manual_direct"
        record["confidence"] = "high"
        record["ttl_until"] = (now_utc() + timedelta(seconds=ttl_seconds)).isoformat()
    write_json(args.state, state)
    refresh_outputs(
        state,
        config,
        args.observed,
        args.vpn_domains,
        args.runtime_config,
        policy_path=args.policy,
    )
    return 0


def command_observe(args: argparse.Namespace) -> int:
    observed = read_observed_domains(args.observed)
    merged = observed[:]
    seen = set(observed)
    for domain in args.domains:
        normalized = domain.lower()
        if normalized in seen:
            continue
        seen.add(normalized)
        merged.append(normalized)
    write_text_if_changed(args.observed, "".join(f"{domain}\n" for domain in merged))
    return 0


def command_policy_show(args: argparse.Namespace) -> int:
    policy = load_policy(args.policy)
    print(yaml.safe_dump(policy, default_flow_style=False, sort_keys=False).strip())
    return 0


def command_policy_add_direct(args: argparse.Namespace) -> int:
    policy = load_policy(args.policy)
    domains = policy.setdefault("always_direct", {}).setdefault("domains", [])
    for target in args.targets:
        normalized = target.lower()
        if normalized not in domains:
            domains.append(normalized)
    save_policy(args.policy, policy)
    pretty.ok(f"Added {len(args.targets)} domain(s) to always-direct")
    return 0


def command_policy_add_vpn(args: argparse.Namespace) -> int:
    policy = load_policy(args.policy)
    domains = policy.setdefault("always_vpn", {}).setdefault("domains", [])
    for target in args.targets:
        normalized = target.lower()
        if normalized not in domains:
            domains.append(normalized)
    save_policy(args.policy, policy)
    pretty.ok(f"Added {len(args.targets)} domain(s) to always-vpn")
    return 0


def command_policy_remove(args: argparse.Namespace) -> int:
    policy = load_policy(args.policy)
    removed = 0
    for target in args.targets:
        normalized = target.lower()
        for section in ("always_direct", "always_vpn"):
            domains = policy.get(section, {}).get("domains", [])
            if normalized in domains:
                domains.remove(normalized)
                removed += 1
    save_policy(args.policy, policy)
    pretty.ok(f"Removed {removed} domain(s) from policy")
    return 0


def command_policy_apply(args: argparse.Namespace) -> int:
    policy = load_policy(args.policy)
    if not policy.get("always_direct", {}).get("domains") and not policy.get("always_vpn", {}).get(
        "domains"
    ):
        pretty.warn("Policy is empty, nothing to apply")
        return 1
    shutil.copy2(args.policy, args.policy_rollback)
    subprocess.run(
        ["systemctl", "--user", "start", "vpn-policy-rollback.timer"],
        capture_output=True,
        check=False,
    )
    changed = policy_sync_to_routing(args.policy, args.runtime_config)
    pretty.ok(
        "Policy applied with 5min auto-rollback timer "
        "(run 'vpn-split-router policy confirm' to keep)"
    )
    if changed:
        pretty.info("Routing config updated")
    return 0


def command_policy_confirm(args: argparse.Namespace) -> int:
    args.policy_rollback.unlink(missing_ok=True)
    subprocess.run(
        ["systemctl", "--user", "stop", "vpn-policy-rollback.timer"],
        capture_output=True,
        check=False,
    )
    pretty.ok("Policy confirmed, rollback timer cancelled")
    return 0


def command_policy_rollback(args: argparse.Namespace) -> int:
    if not args.policy_rollback.exists():
        pretty.warn("No rollback snapshot found")
        return 1
    shutil.copy2(args.policy_rollback, args.policy)
    args.policy_rollback.unlink()
    subprocess.run(
        ["systemctl", "--user", "stop", "vpn-policy-rollback.timer"],
        capture_output=True,
        check=False,
    )
    changed = policy_sync_to_routing(args.policy, args.runtime_config)
    pretty.ok("Policy rolled back to previous state")
    if changed:
        pretty.info("Routing config reverted")
    return 0


def command_policy_sync(args: argparse.Namespace) -> int:
    changed = policy_sync_to_routing(args.policy, args.runtime_config)
    pretty.ok("Policy synced to routing")
    if changed:
        pretty.info("Routing config updated")
    return 0


def add_shared_arguments(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG_PATH)
    parser.add_argument("--state", type=Path, default=DEFAULT_STATE_PATH)
    parser.add_argument("--observed", type=Path, default=DEFAULT_OBSERVED_PATH)
    parser.add_argument("--vpn-domains", type=Path, default=DEFAULT_VPN_DOMAINS_PATH)
    parser.add_argument("--runtime-config", type=Path, default=DEFAULT_RUNTIME_CONFIG_PATH)
    parser.add_argument("--policy", type=Path, default=DEFAULT_POLICY_PATH)
    parser.add_argument("--policy-rollback", type=Path, default=DEFAULT_POLICY_ROLLBACK_PATH)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)

    status_parser = subparsers.add_parser("status")
    add_shared_arguments(status_parser)
    status_parser.set_defaults(func=command_status)

    list_parser = subparsers.add_parser("list")
    add_shared_arguments(list_parser)
    list_parser.set_defaults(func=command_list)

    recheck_parser = subparsers.add_parser("recheck")
    add_shared_arguments(recheck_parser)
    recheck_parser.set_defaults(func=command_recheck)

    forget_parser = subparsers.add_parser("forget")
    add_shared_arguments(forget_parser)
    forget_parser.add_argument("domains", nargs="+")
    forget_parser.set_defaults(func=command_forget)

    mark_vpn_parser = subparsers.add_parser("mark-vpn")
    add_shared_arguments(mark_vpn_parser)
    mark_vpn_parser.add_argument("domains", nargs="+")
    mark_vpn_parser.set_defaults(func=command_mark_vpn)

    mark_direct_parser = subparsers.add_parser("mark-direct")
    add_shared_arguments(mark_direct_parser)
    mark_direct_parser.add_argument("domains", nargs="+")
    mark_direct_parser.set_defaults(func=command_mark_direct)

    observe_parser = subparsers.add_parser("observe")
    add_shared_arguments(observe_parser)
    observe_parser.add_argument("domains", nargs="+")
    observe_parser.set_defaults(func=command_observe)

    policy_parser = subparsers.add_parser("policy")
    policy_sub = policy_parser.add_subparsers(dest="policy_command", required=True)

    show_parser = policy_sub.add_parser("show")
    add_shared_arguments(show_parser)
    show_parser.set_defaults(func=command_policy_show)

    add_direct_parser = policy_sub.add_parser("add-direct")
    add_shared_arguments(add_direct_parser)
    add_direct_parser.add_argument("targets", nargs="+")
    add_direct_parser.set_defaults(func=command_policy_add_direct)

    add_vpn_parser = policy_sub.add_parser("add-vpn")
    add_shared_arguments(add_vpn_parser)
    add_vpn_parser.add_argument("targets", nargs="+")
    add_vpn_parser.set_defaults(func=command_policy_add_vpn)

    remove_parser = policy_sub.add_parser("remove")
    add_shared_arguments(remove_parser)
    remove_parser.add_argument("targets", nargs="+")
    remove_parser.set_defaults(func=command_policy_remove)

    apply_parser = policy_sub.add_parser("apply")
    add_shared_arguments(apply_parser)
    apply_parser.set_defaults(func=command_policy_apply)

    confirm_parser = policy_sub.add_parser("confirm")
    add_shared_arguments(confirm_parser)
    confirm_parser.set_defaults(func=command_policy_confirm)

    rollback_parser = policy_sub.add_parser("rollback")
    add_shared_arguments(rollback_parser)
    rollback_parser.set_defaults(func=command_policy_rollback)

    sync_parser = policy_sub.add_parser("sync")
    add_shared_arguments(sync_parser)
    sync_parser.set_defaults(func=command_policy_sync)

    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
