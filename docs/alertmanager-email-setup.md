# TODO: Configure Alertmanager email delivery

This host is wired to send Alertmanager notifications to `serg.zorg@gmail.com` via Gmail SMTP, but credentials are provided via a SOPS‑managed env file that is not yet created. Until the secret exists, emails will not be sent.

## Where it’s configured
- Prometheus → Alertmanager wiring and alert rules: `hosts/telfir/services.nix`
- Alertmanager SMTP config uses environment variables: `$ALERT_SMTP_USER`, `$ALERT_SMTP_PASS`
- Secret path expected by NixOS: `sops.secrets."alertmanager/env"` → file `secrets/alertmanager.env.sops`

## Steps to enable email delivery
1) Create a Gmail App Password
   - Enable 2‑Step Verification for the Google account.
   - Generate an App Password (select “Mail” → “Other”). Keep the 16‑character password.

2) Create a plaintext dotenv with credentials
   - File content (`secrets/alertmanager.env`, do NOT commit):
     ALERT_SMTP_USER=serg.zorg@gmail.com
     ALERT_SMTP_PASS=<APP_PASSWORD>

3) Encrypt with SOPS using the repo’s `.sops.yaml`
   - Encrypt and replace with `.sops` file:
     sops -e secrets/alertmanager.env > secrets/alertmanager.env.sops
     rm -f secrets/alertmanager.env
   - Alternatively (edit inline):
     sops -e -i secrets/alertmanager.env.sops
     # then add the two lines and save/exit

4) Apply the configuration
   - Build + switch:
     sudo nixos-rebuild switch --flake .#telfir
   - Check services:
     systemctl status alertmanager prometheus

5) Test delivery (optional)
   - Trigger a test alert via Alertmanager API:
     curl -XPOST -H 'Content-Type: application/json' \
       http://127.0.0.1:9093/api/v2/alerts -d '[{
         "labels": {"alertname": "TestEmail", "severity": "critical"},
         "annotations": {"summary": "Test email", "description": "Manual test"}
       }]'
   - Confirm receipt at `serg.zorg@gmail.com`.

## Notes
- Current SMTP settings (in Nix):
  - smarthost: `smtp.gmail.com:587`
  - from: `serg.zorg@gmail.com`
  - TLS: required
- To use a local MTA instead, switch Alertmanager `global.smtp_*` to `127.0.0.1:25` and configure Postfix/msmtp as a relay.
- Firewall exposes Prometheus (9090) and Alertmanager (9093) only on interface `br0`.
