#!/usr/bin/env bash
# Render one rollout report in two shapes:
#
#   plain  a compact text body for ntfy and the desktop toast, which show a
#          summary and cut long text anyway;
#   html   the Telegram message, parsed by the Bot API in HTML parse mode:
#          a bold title with a status emoji, a bold header per section, one
#          bullet per line (a leading git hash becomes inline code) and the
#          failure log inside an expandable block quotation.
#
# Usage:
#   nixos-rollout-report <plain|html> <kind> <title> <meta> \
#     [<section-name> <section-text>]...
#
# Sections are name/text pairs; an empty text skips the section. Two names are
# special: "@note" renders as one unlabelled line (time, reboot hint) and
# "Журнал" as the collapsed log. `kind` picks the status emoji and is one of
# applied, blocked or failed-*; the text is Russian because a human reads it,
# while this comment set stays English like the rest of the repo.
#
# Every dynamic string goes through jq's @html, so a commit subject or a log
# line containing <, & or a quote cannot break the markup.
set -euo pipefail

mode=${1:?usage: nixos-rollout-report <plain|html> <kind> <title> <meta> [<name> <text>]...}
kind=${2:?kind}
title=${3:?title}
meta=${4:?meta}
shift 4

case "$kind" in
  applied) icon='✅' ;;
  blocked) icon='⛔' ;;
  failed-*) icon='⚠️' ;;
  *) icon='ℹ️' ;;
esac

# HTML escaping for the Bot API: &, <, > and both quote characters. The API
# accepts numeric entities, so jq's @apos is rewritten to &#39; — only the
# numeric form is guaranteed there.
esc() {
  printf '%s' "$1" | jq -Rsr '@html' | sed 's/&apos;/\&#39;/g'
}

# `nix store diff-closures` writes SGR colour codes even into a pipe (it has no
# --color flag and ignores NO_COLOR/CLICOLOR), and the watcher feeds its lines
# into these reports. Telegram, ntfy and notify-send do not render them: the
# ESC byte is dropped somewhere and the recipient sees a literal "[32;1m".
# Strip the escapes once, before either shape builds its blocks.
strip_ansi() {
  printf '%s' "$1" | sed -E 's/\x1b\[[0-9;]*m//g'
}

# One line of a bullet section. A short first token that looks like a git hash
# is rendered as inline code; everything else stays text and is escaped.
bullet() {
  local line=$1 head rest
  head=${line%% *}
  if [ "$head" != "$line" ] && [[ $head =~ ^[0-9a-f]{7,40}$ ]]; then
    rest=${line#* }
    printf '• <code>%s</code> %s' "$(esc "$head")" "$(esc "$rest")"
  else
    printf '• %s' "$(esc "$line")"
  fi
}

section_html() {
  local name=$1 text=$2 line
  case "$name" in
    "@note")
      printf '<i>%s</i>' "$(esc "$text")"
      ;;
    "Журнал")
      printf '<b>%s</b>\n<blockquote expandable>' "$(esc "$name")"
      while IFS= read -r line; do
        [ -n "$line" ] && printf '%s\n' "$(esc "$line")"
      done <<< "$text"
      printf '</blockquote>'
      ;;
    *)
      printf '<b>%s</b>' "$(esc "$name")"
      while IFS= read -r line; do
        [ -n "$line" ] && printf '\n%s' "$(bullet "$line")"
      done <<< "$text"
      ;;
  esac
}

section_plain() {
  local name=$1 text=$2
  case "$name" in
    "@note") printf '%s' "$text" ;;
    *) printf '%s:\n%s' "$name" "$text" ;;
  esac
}

render() { # <html|plain>
  local shape=$1 out="" sep="" name text block
  title=$(strip_ansi "$title")
  meta=$(strip_ansi "$meta")
  if [ "$shape" = html ]; then
    out="$(printf '%s <b>%s</b>' "$icon" "$(esc "$title")")"$'\n'
    out+="$(printf '<i>%s</i>' "$(esc "$meta")")"
    sep=$'\n\n'
  fi
  while [ "$#" -ge 3 ]; do
    name=$2
    text=$(strip_ansi "$3")
    shift 2
    if [ -n "$text" ]; then
      if [ "$shape" = html ]; then
        block=$(section_html "$name" "$text")
      else
        block=$(section_plain "$name" "$text")
      fi
      out+="$sep$block"
      sep=$'\n\n'
    fi
  done
  printf '%s' "$out"
}

case "$mode" in
  html | plain) render "$mode" "$@" ;;
  *)
    echo "nixos-rollout-report: unknown mode '$mode' (expected plain or html)" >&2
    exit 2
    ;;
esac
