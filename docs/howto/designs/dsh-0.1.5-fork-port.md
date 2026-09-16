# dsh 0.1.5: porting the plugin family off the removed 0.1.1 contracts

Plan for re-enabling the six plugin rows that the 0.1.5-rc.1 upgrade disabled, and for rewriting the
one plugin whose transport contract was removed rather than renamed.

> **Archived (2026-09).** The dsh web GUI and its `dsh-web-ui` fork checkout were removed in
> 2026-09; the `dsh-market.nix`, `dsh-web-en-assets/` and `dsh-startup-guard*` modules referenced
> below are gone too. This plan describes the removed setup and is kept as history.

Context and the break inventory lived in the dsh-web forks notes (section "dsh 0.1.5-rc.1: SDK
breaks and the rows disabled meanwhile") — that note was removed in 2026-09. Current state: `ssh`,
`live-stats`, `describe-image`, `ui-web-ui-settings`, `remote-web-ui`, `web-search-free` are
`disabled: true` in the profile patch; everything else runs.

Status: A0 (the harness is `scripts/dev/check-dsh-sessions.sh`), A1's roster tokens and A4 are done;
A5 is blocked on the fork's dependency wiring — see "A2. Give the fork its own dependency tree". The
client halves still import the removed runtime primitives, so the section A1b below is the actual
code work.

## Definition of done

- The fork checkout `~/src/1st-level/@projects/dsh-web-ui` — removed in 2026-09 — installs,
  typechecks, builds and tests against `@deepseek-ai/*@0.1.5-rc.1` (`pnpm install`,
  `pnpm typecheck`, `pnpm -r build`, `pnpm -r test`, `pnpm docs:check`, `pnpm aggregate:check`).
- All six rows are enabled again and the web UI boots with no "did not activate" banner.
- Phone pairing works end to end (QR → `/m` surface) with the LAN gate unchanged.
- `dsh-preflight` reports no host-smoke failures (its two known false positives are fixed or
  suppressed, see Verification).

## Blockers (verified)

| Removed upstream                                                             | Evidence                                                                                                                           | Who is blocked                                                                                                                                     |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `@deepseek-ai/dsh-client-runtime`                                            | not published at 0.1.5 (`next` tag = `0.1.1-rc.2`), absent from the harness tree                                                   | the browser halves of 10 fork packages declare it in `dsh.client.inject`; this is what makes the fork's `pnpm install` fail against the 0.1.5 line |
| `@deepseek-ai/dsh-host-apiproxy` (the `apiProxy` service)                    | absent from the 0.1.5 tree; replaced by the Typert gateway (`ctx.typertGateway` host, `ctx.remote` client) plus per-domain Remotes | `dsh-remote-web-ui` — its whole `/m/api` mobile data channel                                                                                       |
| `installSettingsSection` / `settingsNamespace` (`@deepseek-ai/dsh-settings`) | 0.1.5 exports only the service class and `SettingsConflictError`                                                                   | already ported in the fork working tree (settings call sites in 8 files)                                                                           |
| `dsh-free-search` (npm, third-party)                                         | 0.4.24 still imports the removed settings helpers                                                                                  | external — the row stays disabled until its author releases                                                                                        |

## Workstream A — fork toolchain unblock

- **A0. Land the session-read regression harness** in this repo as
  `scripts/dev/check-dsh-sessions.sh` plus a companion `.mjs`: it decodes every stored artifact
  through `sessionFormatCatalog.createRestore` and reports failures grouped by class. This is the
  gate for the `dsh` package patches and the regression alarm for the next upgrade.

- **A1. Replace the removed client token.** Rule: a bundle's roster entry must name the client
  plugins that provide the services its `const inject = [...]` uses. Map
  `@deepseek-ai/dsh-client-runtime` to the concrete providers:

  | service injected | providing package                         |
  | ---------------- | ----------------------------------------- |
  | `slots`          | `@deepseek-ai/dsh-client-ui-renderer`     |
  | `sessions`       | `@deepseek-ai/dsh-api-session-controller` |
  | `uiConversation` | `@deepseek-ai/dsh-client-ui-conversation` |
  | `locale`         | `@deepseek-ai/dsh-client-locale`          |
  | `connection`     | `@deepseek-ai/dsh-client-connection`      |
  | `settingsScope`  | `@deepseek-ai/dsh-client-ui-settings`     |
  | `remote`         | `@deepseek-ai/dsh-api-gateway`            |

  Packages to touch (all declare the dead token): `dsh-aionui-panel`, `dsh-git-graph`,
  `dsh-live-stats`, `dsh-pet`, `dsh-remote-web-ui`, `dsh-ssh`, `dsh-task-board`,
  `dsh-tool-describe-image`, `dsh-web-ui-settings`, `skins/skin-center`. Reference implementation:
  `dsh-widgets` and `dsh-osm` in this repo (already migrated).

- **A1b. Re-point the removed runtime primitives.** The roster token was only half of it: the client
  halves still import values and types from `@deepseek-ai/dsh-client-runtime/client`. Verified
  replacements (all present in the 0.1.5 line):

  | imported from the removed runtime                                 | 0.1.5 source                                                                                              |
  | ----------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
  | `ClientContext`                                                   | `import type { Context as ClientContext } from '@deepseek-ai/cordis'`                                     |
  | `createSnapshotStore`, `defineStore`, store handle/instance types | `@deepseek-ai/dsh-client-store` (npm-only package, bundled into upstream clients)                         |
  | `SettingsScope`, `SettingsScopeSpec`, `SettingsScopeSnapshot`     | `@deepseek-ai/dsh-client-ui-settings`                                                                     |
  | `UseProjection`                                                   | `@deepseek-ai/dsh-client-ui-session` (or `@deepseek-ai/dsh-api-session-controller` for the non-hook face) |
  | `SessionId`                                                       | `@deepseek-ai/dsh-session/types`                                                                          |
  | slot types and the `LocaleNamespaceMap` augmentation              | `@deepseek-ai/dsh-client-ui-slots` (npm-only types package, keep bumped)                                  |

  Importers: `dsh-ssh`, `dsh-aionui-panel`, `dsh-git-graph`, `dsh-live-stats` (four client files),
  `dsh-pet` (three client files), `dsh-task-board`, `dsh-tool-describe-image`,
  `dsh-web-ui-settings`, `dsh-remote-web-ui`. Run `tsc --noEmit` per package after each file to keep
  the list honest.

- **A2. Give the fork its own dependency tree.** The fork's `node_modules` is currently a symlink to
  `~/.dsh/profiles/web/node_modules`, so the SDK comes from the running harness tree — which is why
  `pnpm install`/`pnpm typecheck` stop with `ERR_PNPM_UNSAFE_MODULES_DIR`: pnpm wants to rewrite a
  modules directory that resolves outside the project, and that guard is correct (the naive fix
  would delete the live profile's `node_modules`). The SDK's client-side packages
  (`@deepseek-ai/dsh-client-store`, `@deepseek-ai/dsh-client-ui-slots`) are npm-only and absent from
  the harness tree, so the fork needs its own install:

  1. `ln -s "$(readlink node_modules)" /tmp/fork-node-modules-link` — record the current wiring.
  1. `rm node_modules` — removes the symlink only; the profile's directory stays untouched (verify
     with `ls -ld ~/.dsh/profiles/web/node_modules` before and after).
  1. `pnpm install` — real tree from npm at the pinned 0.1.5 line.
  1. Keep the profile wiring in sync manually from then on (the fork's SDK version no longer follows
     the harness); restore the old wiring with
     `rm -rf node_modules && ln -s ~/.dsh/profiles/web/node_modules node_modules` if the fork must
     go back to resolving through the profile.

- **A3. SDK bump** (already applied in the working tree, 102 spec lines across 13 `package.json`):
  `^0.1.0-rc.6` → `^0.1.5-rc.1` for every `@deepseek-ai/*` devDependency except `dsh-host-apiproxy`
  (kept at `^0.1.0-rc.6` until B lands, then deleted) and `@deepseek-ai/cordis` (`^4.0.1`, resolves
  4.0.2). Add `@deepseek-ai/dsh-client-store` (and keep `@deepseek-ai/dsh-client-ui-slots`) to the
  packages that import them.

- **A4. Re-pin the pnpm cooldown exemptions.** `pnpm-workspace.yaml` → `minimumReleaseAgeExclude`:
  set every entry to the versions the 0.1.5 tree actually carries (`@deepseek-ai/*@0.1.5-rc.1`,
  `cordis@4.0.2`, `cosmokit@1.8.3`, `schemastery@3.18.2`); without this pnpm 11's 24 h cooldown
  silently holds the new line back. Keep `@deepseek-ai/dsh-host-apiproxy@0.1.0-rc.6` until B lands.

- **A5. Install, typecheck, build, test.** `pnpm install` → `pnpm typecheck`. Expected error sources
  beyond the settings API: slot type imports (`dsh-client-ui-slots` is types-only and still
  published at 0.1.5, keep it bumped), `ctx.slots` declarations moving to `dsh-client-ui-renderer`,
  the webserver API, and `dsh-api-remotes` type projections. Then `pnpm -r build`, `pnpm -r test`,
  `pnpm docs:check`, `pnpm aggregate:check`, `pnpm sync-shared:check`.

- **A6. Commit in the fork** — one commit for the toolchain/token work, one for the channel rewrite.

Deliverable: the fork builds and tests green against 0.1.5.

## Workstream B — `dsh-remote-web-ui` channel rewrite

**Landed** — see the progress log for the deltas the implementation added to the table below.

The pairing service, the LAN gate and the `/m` surface stay; only the data channel changes.

- **B1. Host injection.** `src/index.ts` `inject = ['webServer', 'apiProxy']` →
  `['webServer', 'sessionController', 'sessionQuery', 'workspaceRegistry']`; drop the
  `ctx.get('apiProxy')` guard and mount the mobile routes unconditionally.

- **B2. Unary dispatch.** In `src/mobile-api.ts`, replace the
  `dispatch(apiProxy, method, payload, rpcId)` table with the 0.1.5 host services:

  | phone method          | 0.1.5 host call                                                                            |
  | --------------------- | ------------------------------------------------------------------------------------------ |
  | `session.list`        | `ctx.sessionController.list({}, signal)`                                                   |
  | `session.search`      | `ctx.sessionController.search(request, signal)`                                            |
  | `session.create`      | `ctx.sessionController.create(request)`                                                    |
  | `session.selectModel` | `ctx.sessionController.selectModel(request)`                                               |
  | `session.rename`      | `ctx.sessionController.rename(request)`                                                    |
  | `session.prompt`      | `ctx.sessionController.prompt(request, signal)`                                            |
  | `session.models`      | `ctx.sessionController.modelCatalog()`                                                     |
  | `session.history`     | `ctx.sessionController.page(request, signal)` or `ctx.sessionQuery.readSession(sessionId)` |
  | `workspace.list`      | `ctx.workspaceRegistry.list()` mapped to the existing view shape                           |

  Shape deltas verified while scoping this (they are why B2 is a mapping, not a rename):

  - **Errors are thrown, not returned.** The controller methods reject with `RemoteError` (`code`,
    `message`); the old ApiProxy returned `{ rpcId, result: { ok: false | true, … } }`. The handler
    must build the phone's `server-response` envelope from a try/catch, so the phone's `callUnary`
    contract survives unchanged.
  - `session.models` — old `SessionModels` (`{ current, routable, groups, failures }`) versus 0.1.5
    `ModelCatalog` (provider groups + failures + the deployment default): the mapping needs the
    session's current selection filled in from `sessionController.list`/`inspect`.
  - `session.history` — the page now carries `records: SessionHistoryRecord[]`, and the phone folds
    `{ event }` entries, so the host side maps records to that entry shape (plus `hasMore` and the
    optional projection baseline).
  - `session.list` — `SessionListValue.items` is `SessionSummary` (`sessionId`, `updatedAt`,
    `running`, `blank`, `cwd?`, `projections?`), which the existing paging cursor can consume
    unchanged.
  - `workspace.list` — `workspaceRegistry.list()` rows map onto the phone's `workspaceId`/`path`
    view (`WorkspaceView`).
  - `session.history` also stops importing `@deepseek-ai/dsh-host-apiproxy` in the phone's own
    `src/mobile/api.ts`: those types move into the plugin's mobile contract.

- **B3. Event stream.** Replace `apiProxy.events.mux(...)` in the `/m/api/events` SSE handler with
  the controller's own streams: `ctx.sessionController.follow(request, signal)` (opening snapshot,
  gap-free durable frames, optional assistant-stream frames) and
  `ctx.sessionController.control(signal)` for the live-control baseline. Map `SessionFollowFrame` /
  `SessionControlFrame` onto the frame vocabulary the phone already folds
  (`{ type: 'session/event', sessionId, event }` in `src/mobile/messages.ts`). This mapping is the
  real work of the port; the phone's SSE-stall polling fallback stays as a safety net, not as the
  primary path.

- **B4. Wire envelope.** Keep the plugin's own envelope
  (`{ type: 'server-response', rpcId, result: { ok, value | error } }`) and translate a thrown
  `RemoteError` (`code`, `message`) into `result.error`, so the phone client needs no protocol
  change beyond any frame-shape drift from B3.

- **B5. Client half.** `src/client/index.ts` keeps
  `inject = ['slots', 'locale', 'connection', 'settingsScope', 'remote']` (all provided in 0.1.5);
  update its roster tokens per A1 and delete the `@deepseek-ai/dsh-host-apiproxy` devDependency.

- **B6. Tests.** Retarget `src/mobile/mux.test.ts` and `messages.test.ts` at the new frame source;
  add a host test that the dispatch table calls the controller with the expected request (stub ctx).

Deliverable: QR pairing works from a phone, live updates arrive, `requirePairingForLan` and the
`/api` fence behave exactly as before.

## Workstream C — re-enable in this repo

**Landed** — the gate is now a patcher with a pending list (today: `live-stats`, `web-search-free`);
verification in the progress log.

- **C1.** Remove the row lines from the `0.1.5 SDK port pending` block in the
  `modules/user/nix-maid/apps/dsh-market.nix` module (removed in 2026-09) as each plugin is
  verified.
- **C2.** Re-seed the profile copies — those modules copy only when missing, so
  `rm -rf ~/.dsh/profiles/web/node_modules/<pkg>` and let the module's ensure script (or the next
  rebuild/login) re-create it; then `systemctl --user restart dsh.service`. Fork packages are
  symlinked into the fork checkout, so a rebuilt `lib/` is picked up on reload.
- **C3.** Roll out (`sudo -n nixos-rebuild switch --flake .#odin --option substitute false`) and run
  the verification protocol below.

## Workstream D — external

- **D1.** `dsh-free-search`: track the author's release and keep the row disabled meanwhile. If the
  plugin matters before that, vendor the two-line settings-API patch through the former marker-based
  profile patcher pattern (`modules/user/nix-maid/apps/dsh-web-en-assets/patch.mjs`, removed in
  2026-09).

## Verification protocol

- **Session corpus.** `scripts/dev/check-dsh-sessions.sh <installed-dsh-store-path>` → expect 293 of
  294 artifacts readable, with the single known corrupt one
  (`session-50800a3f-8bcf-4d88-acee-691d97eed235`).
- **Client roster.** Load the page with its token and assert that every roster entry's service
  injects are provided by some enabled plugin and that no entry names an absent module token.
- **Boot.** `systemctl --user status dsh.service` active, journal free of loader errors, `/` answers
  the fence (401 for curl), and the boot payload contains the re-enabled plugin ids.
- **Phone.** Manual end-to-end check (QR → `/m`, send a prompt, watch a live update) — there is no
  headless browser in this repo by policy.
- **Preflight.** Its 42 "duplicate entry id" issues and the `dsh-pathlink` / `dsh-memento`
  host-smoke failures are checker false positives (the same tree boots; pathlink exports a Service
  class as `default`, so `plugin.apply(...)` hits `Function.prototype.apply`; memento's apply
  succeeds in the real tree). Fixed in the progress log — the guard now checks duplicates per patch
  file and the two smoke entries are suppressed through its supported `exclude` key.

## Risks and rollback

- The `follow` / `control` frame mapping can degrade silently — the phone falls back to polling and
  looks fine. Force the degraded path in a test before enabling the row.
- The pairing gate is plugin-owned: verify it still refuses non-loopback `/api` requests without a
  paired device after the transport swap.
- Rebuilding the fork touches the six currently-enabled fork plugins (`terminal-ui`, `gui-tweaks`,
  `prompt`, `layout-slash`, `preview`, `selfheal`, `session-archive`) that today run 0.1.1-built
  bundles — budget a drift-triage pass (one page reload per plugin after the rebuild).
- Rollback at any point: re-add the `disabled: true` lines and restart `dsh.service`. The repo-side
  dsh patches (row ids, session-format migration) are independent of this plan.

## Order and rough effort

A (0.5-1 day; the client-primitive re-pointing and the typecheck triage are the unknowns) → B (1-2
days) → C (hours) → D (external). A1-A5 and B1-B4 are independent and can run in parallel; C depends
on both. The A0 harness should land first — it is what keeps the `dsh` package patches honest across
future upgrades.

## Progress log

Done while writing this plan (fork working tree, uncommitted):

- **A0** landed as `scripts/dev/check-dsh-sessions.sh` (+ `.mjs`); the gate reports 293 of 294
  artifacts readable and exits 0 when only the known damaged artifact remains (`--strict` fails on
  it too).

- **A1** — the removed roster token is gone from all ten packages; every token they now declare
  resolves in the 0.1.5 line (`@deepseek-ai/dsh-client-ui-slots` comes from npm, it is types-only).

- **A1b** — 25 client files re-pointed; the three corrections that the first pass missed are worth
  recording: the settings types (`SettingsScope*`) are exported only from the
  `@deepseek-ai/dsh-client-ui-settings/client` subpath, `UseProjection` lives in
  `@deepseek-ai/dsh-api-session-controller/client` (not in ui-session), and `ctx.sessions` /
  `ctx.slots` need the type-only imports of `dsh-api-session-controller/client` and
  `dsh-client-ui-renderer/client` to pull their Context merges.

- The fork's **platform table** was the real gate: `shared/web-platform.ts` still listed the 0.1.1
  seeds and `shared/tsdown.client.ts` carried the documented `RUNTIME_STORE_EXEMPTION`
  (`@deepseek-ai/dsh-client-runtime/client`) for the snapshot-store engine. The 0.1.5 shell seeds
  `react*`, `@deepseek-ai/cordis`, `@deepseek-ai/dsh-client-store`,
  `@deepseek-ai/dsh-client-ui-slots`, `@deepseek-ai/dsh-client-ui-primitives`,
  `@deepseek-ai/dsh-client-ui-dockkit` — the table now mirrors that exactly and the exemption is
  gone (the store engine is a platform module again).

- `shared/client/settings/settings-form.ts` is the source of the per-plugin generated copies
  (`pnpm sync-shared` writes 19 consumers), so import rewrites belong there, not in the copies.

- **A2/A3/A4** — the fork has its own `node_modules` now (`pnpm install --no-frozen-lockfile` exits
  0), the SDK devDependencies are at `^0.1.5-rc.1`, and the cooldown exemptions are re-pinned.

- **A5 (build green)** — `pnpm install --no-frozen-lockfile` and `pnpm -r build` both exit 0: the
  whole 32-project workspace compiles against 0.1.5. Reaching that needed a second wave of ports
  beyond the import sweep:

  - live-stats' projection: `assistant/chunk` → `assistant/attempt` (the attempt carries the packed
    `AssistantStreamRecord[]`, expanded back into timestamped deltas so the throughput window keeps
    its cadence), `schema` → `stateSchema` + `wire: { viewSchema, view }`, the surface buffer became
    a JSON-safe pair array (projection state is persisted and re-parsed), `surfaceOp` replacement
    endpoints are `startSeq`/`endSeq`, `system/message` joined the surface (`EpochHeader.system` is
    gone), and the factory's return type spells the required-`wire` face `register` asks for;
  - pet's phase projection: same `assistant/attempt` switch, phases derived from the record kinds;
  - task-board's client wiring: `SessionBinding` → its `SessionDriver` adapter with the
    completed-turn counter derived from `binding.eventSource` `turn/end` entries (0.1.5's snapshot
    has no `turnEnds`), `workspaces.connectWorkspace` → `sessions.create({ workspaceId })`, the
    cold-read `connection.api.sessions.history` fallback dropped (no direct client counterpart; the
    reconcile ladder falls back to its other signals), workspace list mapped from
    `{ items, archivedSessionIds }` (no recency field);
  - remote-web-ui's client half: the workspace target is an injected `workspaceId` prop (the removal
    of `useWorkspaces` from the standard props), `connectWorkspace` → `sessions.create`,
    `GlobalStandardProps` is empty now (the stale `useSessions` stub had to go);
  - describe-image: `SessionInput.addImages` → `addAttachments`;
  - the dead-import sweep also had to cover `tests/`: three suites mocked the store engine through
    the removed package (`vi.mock('@deepseek-ai/dsh-client-runtime/client')` →
    `vi.mock('@deepseek-ai/dsh-client-store')`).

- **A5 (tests)** — `pnpm -r --no-bail test`: **13 failed / 1114 passed**, and both remaining causes
  are either environment or pending a decision (below). Fixture work completed in this pass:

  - describe-image 44 → 0 (148/148): 0.1.5 renamed the `CallId` brand function to `ToolCallId`;
  - remote-web-ui 4 → 0 (174/174): fixtures updated for the injected `workspaceId` prop and
    `sessions.create({ workspaceId })` (the removed `workspaces.connectWorkspace`);
  - pet 2 → 0 (81/81) and git-graph 3 → 0 (76/76): the helpers now emit `assistant/attempt` with raw
    stream records, and git-graph's bench maps its `composerPhase` option onto the plain `blank`
    snapshot field;
  - git-graph's suite *load* failure, and the same class once `shared` started importing the store:
    vite could not resolve `anser` / `mdast-util-from-markdown` out of the npm copy of
    `dsh-client-ui-primitives`, nor `zustand` / `immer` out of `dsh-client-store`. Those packages
    ship their browser dependencies as `devDependencies` upstream (their own bundles inline them),
    so the npm copies need them resolvable — they now sit in the fork's **root** `devDependencies`,
    which is where vite walks up to from `.pnpm/…`;
  - `shared/package.json` and `scripts/plugin-template/package.json` — the whole fork tree,
    including `scripts/plugin-template/`, was removed in 2026-09 — still carried the dead
    `dsh-client-runtime` dependency and the old `^0.1.0-rc.6` specs (the earlier sweep covered only
    `packages/**`); the template's `dsh.client.inject` now names the renderer.

  Remaining failures:

  - live-stats (12): the fixtures encode whether the TPS row shows in-flight throughput — the
    decision below comes first;
  - ssh (1): the suite spawns `/usr/sbin/sshd`, absent on this host — environment, not a port gap.

  `docs:check` fails on pre-existing fork-doc drift, none of it touched by this port: the bilingual
  triplet is missing for `packages/dsh-terminal-ui` and `packages/dsh-session-archive`, and the
  `packages/dsh-ssh` pair is out of sync with its pairing record. `aggregate:check` and
  `sync-shared:check` pass.

  **Finding for the live-TPS design.** dsh 0.1.5 appends `assistant/attempt` **once, when the
  attempt settles** (`dsh-agent-loop`: `live.settle("assistant/attempt", …)`), and streams in-flight
  deltas as *transient* session frames (`SessionTransientEventEntry` / `AssistantLiveChunkEvent` on
  the event source, delivered through `follow`). A host-side durable projection can therefore price
  only settled attempts: the ported fold is correct and replay-stable, but the row's in-flight TPS
  needs the transient path on the client. Decide that before retargeting the live-stats fixtures,
  because the fixtures encode which of the two the row promises.

- **B (host channel) — landed; `dsh-remote-web-ui` is 174/174 with `tsc` clean.**

  - **B1** `inject` is `['webServer', 'sessionController', 'sessionQuery', 'workspaceRegistry']`;
    the `apiProxy` guard and its `console.warn` are gone (the routes mount unconditionally).
  - **B2** the dispatch table calls `sessionController.*` and maps `workspaceRegistry.list()` rows
    to the phone view. Two shape deltas mattered in practice: the registry row already carries the
    client-facing fields (`title`, the accounted `sessionIds`, the instants), and `SessionSummary`'s
    `running`/`blank` are non-optional, so the phone contract spells them required.
    `session.history` without a session id is an error, not an empty page — the envelope carries
    `{ ok: false, error: { code, message } }` built from the thrown `RemoteError`.
  - **B3** the SSE channel follows `sessionController.control(signal)` and
    `follow({ address, assistantStream: true }, signal)`. The opening snapshot is flattened into
    ordinary `session/event` frames — the phone's fold is idempotent, so a separate baseline frame
    would only add a reset arm — while `control()`'s projection frames become `session/projection`
    (the chat view's admitted-round counter) and everything else rides `host/frame`. Transient
    assistant-stream frames are dropped: the phone prices durable events only.
  - **B4** the envelope is unchanged from the phone's point of view; `src/mobile/contract.ts` now
    owns the wire types that used to be imported from `dsh-host-apiproxy` (9 files re-pointed).
  - **B5** the client half keeps its 0.1.5 injects; the `@deepseek-ai/dsh-host-apiproxy`
    devDependency is gone.
  - **B6** the two transport suites were retargeted rather than deleted: `mux.test.ts` feeds bare
    frames (the bridge no longer wraps them) and filters the live frame by its `seq`, because the
    polling fallback replays durable events too; `mobile-api.spec.ts` stubs the three host faces.
    The fork's `shared` suite is green again as well (24/24) — its earlier
    `@deepseek-ai/dsh-client-store` resolve failure came from the missing root-level browser deps.
  - Dead-token sweep, second pass: the eight `tsdown.config.ts` externals, `mobileBundle`'s
    `dsh-host-apiproxy/api` resolve arm (and its now-unused `createRequire`), the prepare config's
    `libExternal`, the two `pnpm-workspace.yaml` cooldown pins, and the `settings.notExposed` copy
    in four plugins (it named the removed `WEB_SETTINGS_NAMESPACES` allowlist, so the four locales
    now point at the host settings service instead).

- **C (re-enable) — landed and verified live.** The gate is no longer a one-shot append: the new
  `rowGatePatch` rewrites the disabled block in `cordis.patch.yml` from the pending list at its call
  site, so porting the next plugin is a one-word edit. Pending today: `live-stats` (the live-TPS
  decision) and `web-search-free` (`dsh-free-search`, npm-only, no fork counterpart).

  Three ported plugins are now linked straight from the checkout — `@linxin666/dsh-remote-web-ui`,
  `@linxin666/dsh-tool-describe-image` (row `describe-image`) and
  `@linxin666/dsh-client-ui-web-ui-settings` (row `ui-web-ui-settings`) — each as a workspace
  dependency plus a `node_modules` symlink over the stale npm copy, with the standalone bundle row
  stripped (the `ssh` block's treatment, which the bundle patch's duplicate-id abort forced). Note
  the name/directory mismatch: the settings plugin's package is
  `@linxin666/dsh-client-ui-web-ui-settings` while its directory is `packages/dsh-web-ui-settings`.

  Verification after the rollout: the boot log carries no `loader entries failed`,
  `dsh --profile web --dump-config` shows those four rows without `disabled: true` (and the two
  pending rows with it), `/m` answers 200, `POST /m/api/session.list` answers 403
  `{"ok":false,"error":{"code":"unpaired"}}`, and the fence still answers 401 on `/`. The same dump
  warns about two stale patch entries (`dream-skin`, `better-sidebar`) that no row provides —
  pre-existing profile drift, harmless to boot.

  **Pitfall to keep.** The gate block must be rendered at the top level (column 0): the first
  rollout appended it at the old four-space indent, which nested the rows under whichever entry ends
  the file (there, the model-selection `config` block) and aborted boot with
  `bad indentation of a mapping entry (256:5)`. The restart loop hid it until the journal was read.

- **live-TPS decision: hybrid (c), implemented.** The host projection stays the settled truth (0.1.5
  commits one durable `assistant/attempt`, so a host fold cannot price in-flight output at all —
  `SessionLiveEventEntry` / `assistant/live-chunk` exist only in the client contract, and the client
  connection already subscribes to them). The new `src/client/live-rate.ts` prices those transient
  rows with the same estimator and the same `live-stats` settings, and is mounted through the
  composer dock:

  - `TpsLine` now takes an optional `liveRate` and prefers it, falling back to
    `useProjection('liveTokenUsage')` between attempts (the projection's resident rate);
  - the dock entry is finally **registered** (`conversation.composer.dock`) — it was exported but
    never mounted before, which is what left the row invisible (and what the client-apply test
    asserted); its inject factory builds the per-session live source from `ctx.sessions.binding(id)`
    `.eventSource`;
  - the phone channel still drops `assistant-stream` frames, which is not a gap: the mobile UI has
    no throughput consumer at all (`src/mobile/**` never reads `liveTokenUsage` or a
    tokens-per-second value), so forwarding would be dead wire until that surface wants a number.

  Typing trap worth keeping: this package compiles as one host+client program, and importing the
  `@deepseek-ai/dsh-session` main entry (directly or transitively, e.g. through the projection
  package) merges the Host service into `Context`, shadowing the client `ctx.sessions` with
  `SessionStore`. Host files must use the `/types` + `/surface` subpaths (the latter is documented
  browser-safe), and the one remaining client-service read carries a documented cast.

- **live-stats fixtures rewritten to 0.1.5 shapes** (`tests/projection.spec.ts`,
  `tests/estimator.spec.ts`): the suite authored `assistant/chunk` events, which no longer exist (0
  occurrences in the 0.1.5 session types), and `request/header` with `header.system`, which the
  validator rejects (`must omit header.system; use system/message`); the replace op is
  `{ op: 'replace', startSeq, endSeq }` and `assistant/message` must not cite `sourceEventSeqs`.
  Helpers now emit `assistant/attempt` with timed stream records, a `system/message` surface node,
  and the same 18 tests pass. Two expectations changed **meaning**, not just shape:

  - "per chunk" is now "per committed attempt" (a committed attempt rebuilds the step from its own
    stream, so a test that streamed three chunks commits attempts whose streams re-state the
    deltas);
  - input tokens grow where a system prompt is involved (14 → 18, 5 → 9): 0.1.5 dropped
    `EpochHeader.system`, so the rendered prompt is priced as a surface message (block + role
    framing) instead of header text.

- **C complete** — `live-stats` is out of the gate (pending: `web-search-free` only), linked from
  the checkout like the other ported plugins. Verification: package 29/29 with `tsc` and the bundle
  build clean, fork 1147 passed / 1 failed (the `sshd`-less environment test), rollout boot clean
  (`loader entries failed` count 0, fence 401), composed profile shows the row without
  `disabled: true`. **No visual UI check was performed** — driving a browser is banned by repo
  policy and the desktop tool is unavailable in that session; the dock wiring is covered by the
  client-apply and tps-line cases instead.

- **D (external) closed without vendoring.** `dsh-free-search` **0.4.24** (published 2026-09-03)
  already speaks the 0.1.5 settings API — it imports `SettingsProvider`, calls
  `sctx.settings.installSection(ctx, NS, Config, …)` with plain namespace strings, and keeps the
  removed module-level helpers only behind `typeof` guards — so no third-party patch was needed. The
  `web-search-free` row is enabled again and the gate block is gone entirely (every row enabled).
  The ensure script pins `^0.4.24` for fresh installs and upgrades a profile that predates it (this
  one was 13 releases behind, at 0.4.11).

  Two facts recorded with it:

  - the plugin ships Chinese-centric defaults (`lang: zh`, `bingMarket: zh-CN`, and
    `v2ex`/`bilibili` in its platform list). The profile now pins `lang: en` + `bingMarket: en-US` —
    `bingMarket` takes precedence over the lang profile, hence both keys. The platform list is left
    as shipped;
  - Bing (its default provider) answers from this host (HTTP 200), while DuckDuckGo's HTML endpoint
    does not (TLS connect failure), so a provider switch to ddg would fail here.

  The end-to-end *tool* call is not verified: the running agent session predates the row, and a
  fresh session (or the web UI) is needed to invoke it.

- **Profile hygiene, same pass.** The disabled-panel block still carried `dream-skin` and
  `better-sidebar`, ids the 0.1.5 plugin set no longer ships — dsh reported both on every boot
  (`patch: entry … not found`). A new `staleRowsPatch` caretaker drops such rows wherever they stand
  (idempotent; only `- id: X` + `disabled: true` pairs), and `dsh --profile web --dump-config` is
  warning-free now.

- **Post-port: the theme's upstream selectors re-derived (fork commit `67f80f12`).** The neg theme
  (`packages/dsh-terminal-ui`) restyles the host UI by CSS-module class, and every hash in it came
  from the 0.1.1 bundles. 0.1.5 rebuilt those modules — the conversation UI split into
  `dsh-client-ui-chat` / `-tool` / `-approval` — so **24 of its 63 targets matched nothing**: the
  layout rules stopped applying *and* the rules that hide stock chrome stopped hiding it, which
  reads as "the theme was rolled back" while the page still loads. The same class of rot hit
  `dsh-tool-describe-image`, whose decorator anchored on `.Md3f7G_flowItem` and silently stopped
  appending preview strips (fork commit `92ad2496`).

  Method worth repeating on the next upgrade: match the old family to the served one by **suffix
  set** (e.g. `column`/`flowItem`/`turnStatus` -> `EvIC1a`, overlap 1.00; `bubble`/`userRow` ->
  `Sixlwa`, 0.77), or match a rule by its declarations (`--dsh-chat-content-width` identified the
  stats pill row). Only the *theme* was affected: the other host-patching plugins (`dsh-gui-tweaks`,
  `dsh-prompt`, `dsh-layout-slash`, `dsh-osm`, `dsh-widgets`) select by stable attributes and ARIA
  roles, and a repository-wide sweep of quoted selectors in plugin bundles found no other stale
  hash. Verification is a scan of every class/attribute the theme names against all served bundles
  (`@deepseek-ai/**` plus fork and local plugins, symlinks followed): zero dead targets, and the
  served plugin group carries the new selectors.

- **Preflight false positives fixed (guard patch + suppression).** The `dsh-startup-guard`
  composition check (removed in 2026-09 with the web GUI) concatenated every patch file's entry ids
  and flagged *any* repeat as a loader-level boot failure. On 0.1.5 that is the normal override
  mechanism (`@deepseek-ai/dsh-base` and `@deepseek-ai/dsh-web-app` both ship `tool-bash`/`tools`/…,
  the profile patch overrides `web-runtime`/`agent-presets`, and `@linxin666/dsh-web-ui-all`
  re-declares its sub-plugin rows), so every boot reported 37 web + 1 tui issues while the tree
  booted clean. New module `dsh-startup-guard.nix` (assets `dsh-startup-guard-assets/`, removed in
  2026-09) re-applied two things at activation and login, because a pnpm re-install overwrote the
  plugin:

  - `guard-patch.mjs` scopes the duplicate check to one patch file (a same-file repeat stays fatal,
    so strict mode still blocks real authoring bugs). Idempotent through a sentinel comment, with an
    `.orig` backup and a `node --check` pass before the live file is replaced.
  - `guard-config.json` adds the guard's supported `exclude` for `dsh-pathlink` and `dsh-memento` —
    their host-smoke failures are the two documented checker false positives, and suppression is the
    remedy the guard README offers (`exclude` skips the client-validity and host-smoke passes for
    those two bundles; everything else stays guarded).

  Verified with `compositionPreflight` directly against the live profiles (37 → 0 web, 1 → 0 tui;
  same-file duplicates still reported) and with a full `runGuard` dry-run (issues 0, `brokenHost` 0,
  broken 0, `fixNeeded` 0). Upstream note: the guard's own test *"composed stack duplicate entry ids
  are reported as loader-level issues"* encodes the cross-file behavior we now treat as an override;
  a proper upstream fix should make that check layer-aware.
