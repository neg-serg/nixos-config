# Grafana admin password (SOPS)

This repo wires Grafana to read the admin password from a SOPS-encrypted file and feed it via
Grafana's $\_\_file provider. Nothing is required if you are fine with the default `admin/admin` on
first start, but you should set a strong password before exposing the UI.

Two supported file names (first found is used):

- `secrets/grafana-admin-password.sops.yaml` (recommended)
- `secrets/grafana-admin-password.sops` (binary alternative)

The decrypted content must be a single-line password (no YAML keys), because it is passed to Grafana
as a file reference.

## Quick setup (recommended, YAML scalar)

1. Create the file with a single line (no quotes):

```
echo 'YourStrongPasswordHere' > secrets/grafana-admin-password.sops.yaml
```

2. Encrypt it using SOPS with the repo's age recipients (uses .sops.yaml automatically):

```
sops -e -i secrets/grafana-admin-password.sops.yaml
```

3. Commit the encrypted file:

```
git add secrets/grafana-admin-password.sops.yaml
git commit -m "[secrets] grafana admin password (sops)"
```

4. Rebuild/switch. Grafana will use the password via `$__file{...}`.

## Alternative (binary file)

If you prefer a binary SOPS file named `secrets/grafana-admin-password.sops`, encrypt it explicitly
with the age recipients from `.sops.yaml`:

```
# Recipients from .sops.yaml
AGE1="age1eggdzmjp2h4a68kn0j5zay72s7s6tc7qzak6cy9zp3dj0rwxxetsmz4t52"
AGE2="age1lnkpac97m7drx3k2ej5jwccfa99z4n2sxlezwzjfcevwqtvw9chs8knmtc"

printf '%s' 'YourStrongPasswordHere' > secrets/grafana-admin-password.sops
sops -e \
  --age "$AGE1" --age "$AGE2" \
  --input-type binary --output-type binary \
  -i secrets/grafana-admin-password.sops

git add secrets/grafana-admin-password.sops
git commit -m "[secrets] grafana admin password (sops binary)"
```

## Notes

- The Nix config only reads the secret if the file exists; otherwise Grafana falls back to defaults.
- Resulting secret is installed to a root-only path referenced by Grafana's
  `services.grafana.settings.security.admin_password = "$__file{...}"`.
- You can rotate the password by re-encrypting the file and switching the system.
- For LAN HTTPS, Grafana is served via Caddy at `https://grafana.telfir` with Caddy internal CA.
  Download the CA from `/ca.crt` and add it to your trust store if needed.
