# Runbooks and Operations

Operational docs for one-off tasks (password rotation, migrations) and recurring maintenance
(dashboards, exporters). Script catalog at the bottom groups helpers by domain.

- Alertmanager email setup:
  [runbook-alertmanager-email-setup.md](./runbook-alertmanager-email-setup.md)
- Proxy (Xray / sing-box): [runbook-proxy.md](./runbook-proxy.md)
- Unbound metrics/dashboards: [runbook-unbound-metrics.md](./runbook-unbound-metrics.md)
- Vaultix migration: [runbook-vaultix-migration.md](./runbook-vaultix-migration.md)
- **Repeatable repo audit**: [runbook-audit.md](./runbook-audit.md)
- Debugging slow deploys (`just deploy` ~10s even with no changes):
  [runbook-debug-slow-deploy.md](./runbook-debug-slow-deploy.md)
- Kernel AutoFDO optimization (module exists, not yet wired into the localmodconfig build):
  [runbook-kernel-autofdo.md](./runbook-kernel-autofdo.md)
- Script catalog: [runbook-scripts.md](./runbook-scripts.md)
