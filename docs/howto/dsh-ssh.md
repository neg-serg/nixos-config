# dsh-ssh: SSH operations, web terminal, and localhost for the agent

The `@linxin666/dsh-ssh` plugin provides dsh web with the **Remote SSH** panel (sidebar), a web
terminal (xterm.js), the agent tools
`ssh_list/ssh_exec/ssh_upload/ssh_download/ssh_tunnel/ssh_cluster`, and the slash commands `/ssh*`.
The short version for the agent is the skill `~/.dsh/skills/dsh-ssh/SKILL.md`; here — the host side,
decisions, and limitations.

## How it is enabled

1. **Profile** (`modules/user/nix-maid/apps/dsh-market.nix`):
   - the dependency `@linxin666/dsh-ssh: workspace:^0.1.16` + symlink
     `node_modules/@linxin666/dsh-ssh` → fork
     `~/src/1st-level/@projects/dsh-web-ui/packages/dsh-ssh`;
   - `- id: ssh / disabled: true` is removed from `cordis.patch.yml`. The `ssh` row comes from the
     bundle patch `dsh-web-ui-all`; a separate insert row is not needed (otherwise a duplicate id).
1. **Skin** (`packages/dsh-terminal-ui` in the fork): `display:none` is removed from `.mL8Uca_entry`
   — that is the button that opens the Remote SSH panel.
1. The fork package is already built (`lib/` is committed in the fork).

Rollback: put `- id: ssh / disabled: true` back into the patch and remove the dep/symlink in the
module.

## localhost (odin)

- The `localhost` host uses the dedicated agent key **`~/.ssh/agent/dsh-agent-key`**; in
  `authorized_keys` the entry is restricted with `from="127.0.0.1,::1"` (the personal `id_ed25519`
  remains as a fallback — it is authorized too).
- sshd (`hosts/odin/services.nix` + `modules/servers/openssh`): `openssh.allowTcpForwarding = true`
  - `PermitOpen 127.0.0.1:* [::1]:*` — tunnels are allowed, but **loopback only** (no pivoting into
    the LAN); ⚠️ IPv6 in PermitOpen must be bracketed: `[::1]:*` (without brackets sshd fails with
    "PermitOpen bad port number").
- To widen (if tunnels into the LAN are ever needed): replace PermitOpen with the required host
  masks (`PermitOpen 10.0.2.*:*` etc.) — knowingly; this weakens hardening.

## Hosts

- Storage: `~/.dsh/dsh-ssh.json` (0600, owner neg). An entry: alias, host, port, user, auth {kind:
  key|password, keyPath}, proxyJump[], tags[], environment.
- REST, loopback-only (`http://127.0.0.1:3080/api/dsh-ssh`): `GET/POST /hosts`,
  `PATCH/DELETE /hosts?alias=<x>`, `POST /hosts/import-ssh-config` (import from `~/.ssh/config`,
  existing aliases are skipped), `POST /test`.
- Key authentication requires `auth.keyPath`.
- Web terminal: WS `/api/dsh-ssh/terminal?alias=<x>&cols=120&rows=40`.

## Terminal commands (packages/local-bin/bin)

`ssh-hosts` — list hosts; `ssh-exec [alias] <cmd...>` — run a command; `ssh-test [alias]` —
connectivity check; `ssh-tunnels` — active tunnels. After adding them to the repo,
`nh os switch /etc/nixos#odin --option substitute false`.

## Limitations and decisions

- Tunnels on odin are loopback-only (see above): safe by default.
- `ssh_download` cannot handle directories — files only; `ssh_upload` can.
- `ssh_exec` with auto-reconnect (up to 3 attempts) may replay a non-idempotent command.
- Passwords in `dsh-ssh.json` are plaintext (0600) and never make it into the repo.
- Command output may contain sensitive data.

## Verification

```bash
ssh-hosts; ssh-test localhost; ssh-exec localhost 'hostname'
ssh-tunnels                       # none active
# end-to-end tunnel:
ssh_tunnel(start, localhost:22) → ssh -p <localPort> neg@127.0.0.1
```
