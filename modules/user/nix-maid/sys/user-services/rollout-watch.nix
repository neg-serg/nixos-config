##
# Module: user/nix-maid/sys/user-services/rollout-watch
# Purpose: deploy committed changes to the /etc/nixos checkout without a human
# in the loop. Every `interval` the watcher compares HEAD with the state it last
# handled, runs the repo's own `just check` gate, builds the host toplevel and
# hands the verified store path to the root-owned nixos-agent-rollout service
# (modules/security/agent-switch.nix) — the same path an agent uses by hand in
# .agent/workflows/rebuild.md, now on a timer. The report goes to ntfy, the
# desktop and Telegram. Telegram is the one channel the user unit cannot reach
# on its own: the bot token is root-only (0400), so the watcher queues the
# message and a root oneshot drains the queue through the shared sender.
#
# Why: every change used to end with "now run the switch yourself". The human
# was the last step of every rollout; the timer removes that step while keeping
# the gates (clean tree on the deploy branch, `just check`, and the built-path
# check inside the unit, which still refuses a tree that no longer builds the
# requested artifact).
#
# Gate choice: `just check` (flake eval + checks) and deliberately not
# `just lint`. Lint's tool set depends on the caller's PATH — the system
# rustfmt disagrees with `just lint` about four packages even though the
# commit passed lint in the author's shell — and a lint failure does not make
# the system unbootable. Eval and the checks do.
#
# Cost, spelled out: anything that can write /etc/nixos can now get root
# without even asking, because the switch request is written by the timer, not
# by a human. The gates are `just check` plus the risky-path list, not a
# signature. Flip features.system.rolloutWatch.enable off (and switch once by
# hand) to stop it.
#
# Behaviour notes:
#   - only a clean tree on `branch` is deployed; a dirty tree, another branch
#     or a detached HEAD is left alone and no notification is sent (nothing to
#     report: the human is working);
#   - a manual switch, an agent rollout or a rollback between two ticks rebases
#     the watcher on HEAD instead of fighting it;
#   - the same HEAD is handled once: a failed check or build is not retried
#     every tick, only when a new commit arrives;
#   - state and the logs of the last check/build live in
#     $XDG_STATE_HOME/nixos-rollout-watch (default ~/.local/state).
#
# Key options: features.system.rolloutWatch.{enable,branch,interval,riskyPaths,
# ntfyUrl,desktopNotify,telegramSender}.
# Dependencies: features.security.agentSwitch (the unit it triggers), the repo's
# Justfile (`just check`), config.nix.package.
{
  lib,
  config,
  pkgs,
  ...
}:
let
  inherit (lib)
    mkIf
    getExe
    escapeShellArg
    ;
  cfg = config.features.system.rolloutWatch;

  # Telegram delivery needs the bot token, which is a root-only secret (owner
  # root, mode 0400 in hosts/trantor/telegram.nix): the user-level watcher
  # cannot call the shared sender. It queues a message into a group-writable
  # inbox instead, and a path unit starts a root oneshot that drains the queue
  # through that sender. The only privilege the queue adds is "the desktop user
  # can send a Telegram message as the bot", which is what any notification
  # channel already allows.
  telegramEnabled = cfg.telegramSender != null;
  telegramInbox = "/var/lib/nixos-rollout-telegram/inbox";
  telegramGroup = config.users.users.${config.lib.neg.mainUser}.group;

  telegramDrain = pkgs.writeShellApplication {
    name = "nixos-rollout-telegram-drain";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      set -euo pipefail
      sender=${escapeShellArg (if telegramEnabled then getExe cfg.telegramSender else "/bin/false")}
      inbox=${escapeShellArg telegramInbox}

      # The path unit fires on every new file; drain whatever is queued and
      # delete each message even when delivery fails (a failing Telegram must
      # not turn into an ever-retrying queue).
      shopt -s nullglob
      for msg in "$inbox"/msg-*; do
        title=$(head -n 1 "$msg")
        body=$(tail -n +2 "$msg")
        if ! "$sender" "$title" "$body" 6; then
          echo "telegram: delivery failed for $msg" >&2
        fi
        rm -f "$msg"
      done
    '';
  };

  # Regex prefixes, not globs: the same list filters `git diff --name-only`.
  riskyPattern = builtins.concatStringsSep "|" (map (p: "^" + lib.escapeRegex p) cfg.riskyPaths);

  watchScript = pkgs.writeShellApplication {
    name = "nixos-rollout-watch";
    runtimeInputs = [
      config.nix.package # nix build / nix store diff-closures
      pkgs.git # HEAD, branch, status, diff, log
      pkgs.just # the repo's own `just check` gate
      pkgs.bash # `set shell := ["bash", "-cu"]` in the Justfile
      pkgs.curl # ntfy POST
      pkgs.libnotify # notify-send desktop report
      pkgs.util-linux # flock: one watcher at a time
      pkgs.systemd # systemctl: trigger and wait for the rollout
      pkgs.gnugrep # grep -E for the risky-path filter
      pkgs.coreutils # readlink, seq, sleep, tail
    ];
    text = ''
      # Test seams (used while developing the watcher, not by the timer):
      # ROLLOUT_WATCH_REPO points it at another checkout, ROLLOUT_WATCH_STATE_DIR
      # at a scratch state dir, ROLLOUT_WATCH_DRY_RUN prints the plan instead of
      # switching.
      repo=''${ROLLOUT_WATCH_REPO:-${escapeShellArg cfg.repo}}
      host=${escapeShellArg config.networking.hostName}
      branch=${escapeShellArg cfg.branch}
      risky_pattern=${escapeShellArg riskyPattern}
      ntfy_url=${escapeShellArg (if cfg.ntfyUrl == null then "" else cfg.ntfyUrl)}
      telegram_inbox=${escapeShellArg (if telegramEnabled then telegramInbox else "")}
      desktop_notify=${if cfg.desktopNotify then "1" else "0"}

      state=''${ROLLOUT_WATCH_STATE_DIR:-''${XDG_STATE_HOME:-$HOME/.local/state}/nixos-rollout-watch}
      mkdir -p "$state"

      log() { printf '%s\n' "$*"; }

      read_state() {
        if [ -f "$state/$1" ]; then
          cat "$state/$1"
        fi
      }

      write_state() {
        printf '%s\n' "$2" > "$state/$1"
      }

      # One watcher at a time: a timer tick that lands while the previous build
      # is still running must not start a second rollout.
      exec 9> "$state/lock"
      if ! flock -n 9; then
        log "another watcher is running; nothing to do"
        exit 0
      fi

      # All three channels are best-effort: a dead ntfy, Telegram (the sender
      # egresses through the user socks proxy) or desktop must not change the
      # rollout outcome. The text is Russian: these messages are read by the
      # human, unlike the repo's docs and comments.
      notify() {
        local title=$1 body=$2 prio=''${3:-default} tags=''${4:-}
        body=''${body:0:1500}

        # Test seam: the manual checks in this module's header run the watcher
        # against a scratch repo and must not page a phone.
        if [ -n "''${ROLLOUT_WATCH_NO_NOTIFY:-}" ]; then
          log "notify: suppressed ($title)"
          return 0
        fi

        if [ -n "$ntfy_url" ]; then
          local args=(-fsS -m 10 -X POST -H "Title: $title" -H "Priority: $prio")
          if [ -n "$tags" ]; then
            args+=(-H "Tags: $tags")
          fi
          if ! curl "''${args[@]}" --data-binary "$body" "$ntfy_url" > /dev/null 2>&1; then
            log "notify: ntfy delivery failed"
          fi
        fi

        if [ "$desktop_notify" = 1 ]; then
          local urgency=normal
          case "$prio" in
            low) urgency=low ;;
            high | urgent) urgency=critical ;;
          esac
          if ! notify-send -a nixos-rollout -u "$urgency" "$title" "$body" > /dev/null 2>&1; then
            log "notify: no desktop session for notify-send"
          fi
        fi

        if [ -n "$telegram_inbox" ]; then
          publish_telegram "$title" "''${body:0:900}"
        fi
      }

      # The bot token is a root-only secret (owner root, mode 0400), so the
      # user-level watcher cannot call telegram-send itself. It drops a message
      # file into a group-writable inbox; the root-owned
      # nixos-rollout-telegram service is started by a path unit and drains it.
      # The file is written under a dot name first (the path unit matches
      # `msg-*`) and renamed, so the drain never sees a half-written message.
      publish_telegram() {
        local title=$1 body=$2
        if [ ! -d "$telegram_inbox" ] || [ ! -w "$telegram_inbox" ]; then
          log "notify: telegram inbox unavailable ($telegram_inbox)"
          return 0
        fi
        local stamp tmp
        stamp=$(date +%s%N)-$$
        tmp="$telegram_inbox/.tmp-$stamp"
        printf '%s\n%s\n' "$title" "$body" > "$tmp"
        mv "$tmp" "$telegram_inbox/msg-$stamp"
      }

      short() { printf '%s' "''${1:0:8}"; }

      commits_since() {
        local from=$1 to=$2
        if [ -n "$from" ] && git -C "$repo" cat-file -e "$from^{commit}" 2> /dev/null; then
          git -C "$repo" log --format='%h %s' --reverse "$from..$to" | head -10 || true
        else
          git -C "$repo" log -1 --format='%h %s' "$to" || true
        fi
      }

      head_rev=$(git -C "$repo" rev-parse HEAD)
      branch_now=$(git -C "$repo" symbolic-ref --quiet --short HEAD || true)
      current=$(readlink -f /run/current-system)

      prev_head=$(read_state head)
      status=$(read_state status)
      base=$(read_state base)
      prev_current=$(read_state current)

      log "watch: HEAD=$(short "$head_rev") branch=''${branch_now:-detached} current=$current"

      record() {
        write_state head "$head_rev"
        write_state status "$1"
      }

      # An activation we did not order — a human `nh os switch`, an agent
      # rollout, a rollback — moves the baseline. Rebase quietly on HEAD
      # instead of deploying over it: a rollback is a deliberate act, and the
      # next commit is deployed as usual.
      if [ -n "$prev_current" ] && [ "$current" != "$prev_current" ]; then
        log "external activation: $prev_current -> $current; rebasing on HEAD"
        record ok
        write_state base "$head_rev"
        write_state current "$current"
        exit 0
      fi

      if [ "$head_rev" = "$prev_head" ] && [ -n "$status" ]; then
        log "HEAD $(short "$head_rev") already handled ($status)"
        exit 0
      fi

      if [ "$branch_now" != "$branch" ]; then
        log "HEAD is on ''${branch_now:-a detached head}, not '$branch': not deploying"
        exit 0
      fi

      # Untracked files do not reach a git flake's source, so a stray file in
      # the checkout must not stall the watcher for ever (it would, if it
      # counted as dirt): only tracked modifications are uncommitted work.
      if [ -n "$(git -C "$repo" status --porcelain --untracked-files=no)" ]; then
        log "working tree is dirty: not deploying uncommitted work"
        exit 0
      fi

      # Risky paths: a wrong VPN, secret or security-module change can lock the
      # host out, and the watcher must not be the one to apply it. Report once
      # per commit and leave the machine alone.
      changed=""
      if [ -n "$base" ] && git -C "$repo" cat-file -e "$base^{commit}" 2> /dev/null; then
        changed=$(git -C "$repo" diff --name-only "$base..$head_rev")
      fi
      if [ -n "$changed" ]; then
        risky=$(printf '%s\n' "$changed" | grep -E "$risky_pattern" || true)
        if [ -n "$risky" ]; then
          record blocked
          log "blocked: manual-only paths changed:"
          log "$risky"
          notify "$host: выкатка $(short "$head_rev") ждёт ручного switch" \
            "$(commits_since "$base" "$head_rev")

      Затронуты пути под ручным контролем:
      $risky

      Автодеплой систему не тронул. Выкатить: just switch-sudo" high warning
          exit 0
        fi
      fi

      log "gate: just check"
      if ! ( cd "$repo" && just check ) > "$state/check.log" 2>&1; then
        record failed-check
        notify "$host: выкатка $(short "$head_rev") не прошла just check" \
          "Проверки упали, система не тронута.

      $(tail -c 1200 "$state/check.log")" high warning
        exit 1
      fi

      log "build: $repo#nixosConfigurations.$host.config.system.build.toplevel"
      if ! nix build "$repo#nixosConfigurations.$host.config.system.build.toplevel" \
        --out-link "$state/toplevel" > "$state/build.log" 2>&1; then
        record failed-build
        notify "$host: выкатка $(short "$head_rev") не собралась" \
          "Сборка упала, система не тронута.

      $(tail -c 1200 "$state/build.log")" high warning
        exit 1
      fi
      built=$(readlink -f "$state/toplevel")

      if [ "$built" = "$current" ]; then
        record ok
        write_state base "$head_rev"
        log "the running system already is $built; nothing to deploy"
        exit 0
      fi

      if [ -n "''${ROLLOUT_WATCH_DRY_RUN:-}" ]; then
        log "dry run: would activate $built (current $current)"
        exit 0
      fi

      if systemctl is-active --quiet nixos-agent-rollout-work.service; then
        log "another rollout is in flight; leaving this commit to the next tick"
        exit 0
      fi

      mkdir -p "$repo/.agent"
      printf '%s\n' "$built" > "$repo/.agent/switch-request"

      # nixos-agent-rollout is the constant unit file; the legacy name is what a
      # running generation still knows until the bootstrap block is dropped.
      unit=nixos-agent-rollout.service
      if ! systemctl cat nixos-agent-rollout.service > /dev/null 2>&1; then
        unit=nixos-agent-switch.service
      fi

      started=$SECONDS
      if ! systemctl start "$unit"; then
        rm -f "$repo/.agent/switch-request"
        record failed-activate
        notify "$host: активация $(short "$head_rev") не запустилась" \
          "nixos-agent-rollout не стартовал; система на прежнем поколении." high warning
        exit 1
      fi

      # The launch unit detaches the real work into nixos-agent-rollout-work (a
      # Type=oneshot kept running would deadlock the activation that starts it).
      # Give it a moment to appear, then wait for it to finish.
      for _ in $(seq 1 15); do
        if systemctl is-active --quiet nixos-agent-rollout-work.service; then
          break
        fi
        if [ ! -f "$repo/.agent/switch-request" ]; then
          break
        fi
        sleep 1
      done

      waited=0
      while systemctl is-active --quiet nixos-agent-rollout-work.service; do
        if [ "$waited" -ge 1800 ]; then
          log "timed out waiting for the rollout worker"
          break
        fi
        sleep 2
        waited=$((waited + 2))
      done

      elapsed=$((SECONDS - started))
      new_current=$(readlink -f /run/current-system)

      if [ "$new_current" = "$built" ]; then
        record ok
        write_state base "$head_rev"
        write_state current "$new_current"

        diff=$(nix store diff-closures "$current" "$built" 2> /dev/null | head -8 || true)
        body="Коммиты:
      $(commits_since "$base" "$head_rev")

      Изменения:
      ''${diff:-нет}"
        if [ "$(readlink -f "$current/kernel")" != "$(readlink -f "$built/kernel")" ] ||
          [ "$(readlink -f "$current/initrd")" != "$(readlink -f "$built/initrd")" ]; then
          body+="

      Ядро или initrd сменились: нужна перезагрузка."
        fi
        body+="

      Время: ''${elapsed}s"
        log "activated $built in ''${elapsed}s"
        notify "$host: выкатка $(short "$head_rev") применена" "$body" default white_check_mark
        exit 0
      fi

      if [ "$new_current" != "$current" ]; then
        # The machine moved somewhere else while we waited (a concurrent
        # rollout won, or a human switched). Do not fight it.
        log "the machine moved to $new_current during the rollout; rebasing on HEAD"
        record ok
        write_state base "$head_rev"
        write_state current "$new_current"
        exit 0
      fi

      rm -f "$repo/.agent/switch-request"
      record failed-activate
      log "activation failed; the system stayed at $current"
      notify "$host: активация $(short "$head_rev") упала" \
        "Система осталась на $current.
      Журнал: journalctl -u nixos-agent-rollout-work -n 40
      Откат, если профиль уже сдвинулся: sudo nixos-rebuild switch --rollback" urgent warning
      exit 1
    '';
  };
in
mkIf cfg.enable ({
  systemd.user.services.nixos-rollout-watch = {
    description = "Deploy committed ${config.networking.hostName} changes via nixos-agent-rollout";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = getExe watchScript;
      # A build plus activation takes minutes; the 90 s oneshot default is wrong.
      TimeoutStartSec = "infinity";
      # The watcher only reports: a failed tick is recorded in the state dir and
      # the journal, and the next commit retries. Restarting it would only
      # re-run the same failing gate.
      Restart = "no";
    };
  };

  systemd.user.timers.nixos-rollout-watch = {
    description = "Timer: deploy new /etc/nixos commits";
    timerConfig = {
      OnCalendar = cfg.interval;
      # No catch-up runs: the state file already says what was deployed, and a
      # burst of missed ticks at login buys nothing.
      Persistent = false;
      Unit = "nixos-rollout-watch.service";
    };
    wantedBy = [ "timers.target" ];
  };
  # Telegram queue: only when a sender is configured. mkIf, not
  # `optionalAttrs` — the latter forces cfg.telegramSender while the module's
  # config attrset is being built, which recurses through the host's
  # `lib.mkIf config.trantor.telegram.enable config.trantor.telegram.sender`.
  #
  # The inbox is the only interface between the user-level watcher and the
  # root-level sender: group-writable by the desktop user, nothing else.
  systemd.tmpfiles.rules = mkIf telegramEnabled [
    "d /var/lib/nixos-rollout-telegram 0750 root ${telegramGroup} - -"
    "d ${telegramInbox} 0770 root ${telegramGroup} - -"
  ];

  systemd.services.nixos-rollout-telegram = mkIf telegramEnabled {
    description = "Send queued rollout reports to Telegram";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = getExe telegramDrain;
      # A failed delivery is logged and dropped; retrying a dead proxy would
      # only block the next report behind a stuck unit.
      Restart = "no";
    };
  };

  systemd.paths.nixos-rollout-telegram = mkIf telegramEnabled {
    description = "Start the Telegram drain when a rollout report is queued";
    pathConfig.PathExistsGlob = "${telegramInbox}/msg-*";
    wantedBy = [ "paths.target" ];
  };
})
