# Alertmanager email delivery (not wired yet)

Alerting on this host goes to Telegram: `modules/monitoring/alertmanager/default.nix` renders
`alertmanager.yml` with a `telegram` receiver pointing at the local webhook bridge in
`hosts/trantor/services/telegram-units.nix`. Email delivery does **not** exist in the configuration
today: `global` is empty, there is no `smtp_*` stanza, no `alertmanager/env` secret, and nothing in
the repo reads `ALERT_SMTP_*`. The steps below are the plan; adding them is a Nix change, not just a
secret.

## Where it’s configured

- Prometheus → Alertmanager wiring and alert rules: `hosts/trantor/services/telegram-units.nix`
- Alertmanager SMTP config uses environment variables: `$ALERT_SMTP_USER`, `$ALERT_SMTP_PASS`
- Secret path expected by NixOS: `sops.secrets."alertmanager/env"` → file
  `secrets/alertmanager.env.sops`

## Steps to enable email delivery

1. Wire SMTP in the module: fill `global.smtp_*` in `modules/monitoring/alertmanager/default.nix`
   (smarthost `smtp.gmail.com:587`, from `serg.zorg@gmail.com`, `require_tls = true`), add an
   `email` receiver and route to it, then declare `sops.secrets."alertmanager/env"` so the
   credentials land in `environmentFile`.

1. Create a Gmail App Password

   - Enable 2‑Step Verification for the Google account.
   - Generate an App Password (select “Mail” → “Other”). Keep the 16‑character password.

1. Create a plaintext dotenv with credentials

   - File content (`secrets/alertmanager.env`, do NOT commit): ALERT_SMTP_USER=serg.zorg@gmail.com
     ALERT_SMTP_PASS=\<APP_PASSWORD>

1. Encrypt with SOPS using the repo’s `.sops.yaml`

   - Encrypt and replace with `.sops` file: sops -e secrets/alertmanager.env >
     secrets/alertmanager.env.sops rm -f secrets/alertmanager.env
   - Alternatively (edit inline): sops -e -i secrets/alertmanager.env.sops
     # then add the two lines and save/exit

1. Apply the configuration

   - Build + switch: sudo nixos-rebuild switch --flake .#trantor
   - Check services: systemctl status alertmanager prometheus

1. Test delivery (optional)

   - Trigger a test alert via Alertmanager API: curl -XPOST -H 'Content-Type: application/json' \
     127.0.0.1:9093/api/v2/alerts -d '\[{ "labels": {"alertname": "TestEmail", "severity":
     "critical"}, "annotations": {"summary": "Test email", "description": "Manual test"} }\]'
   - Confirm receipt at `serg.zorg@gmail.com`.

## Notes

- Current SMTP settings (in Nix):
  - smarthost: `smtp.gmail.com:587`
  - from: `serg.zorg@gmail.com`
  - TLS: required
- To use a local MTA instead, switch Alertmanager `global.smtp_*` to `127.0.0.1:25` and configure
  Postfix/msmtp as a relay.
- Firewall exposes Prometheus (9090) and Alertmanager (9093) only on interface `br0`.
