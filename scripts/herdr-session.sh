#!/usr/bin/env bash
# Explicit session picker. No shell startup hook, no eval, no session deletion.
set -euo pipefail
if [ "${1:-}" = --help ]; then
  echo 'Usage: hs [session-name]  (or: bash scripts/herdr-session.sh [session-name])'
  echo 'No argument: choose an existing session or create a named one.'
  exit 0
fi
if [ -n "${HERDR_PANE_ID:-}" ]; then
  echo 'Detach first (Ctrl+B, then Q), then run hs from the outer shell.' >&2
  exit 1
fi
command -v herdr >/dev/null || { echo 'herdr is missing; run ./install.sh ghostty' >&2; exit 1; }
[ "$#" -le 1 ] || { echo 'Usage: hs [session-name]' >&2; exit 1; }
if [ "$#" -eq 1 ]; then
  [ -n "$1" ] || { echo 'Session name cannot be empty.' >&2; exit 1; }
  exec herdr --session "$1"
fi
command -v jq >/dev/null || { echo 'jq is missing; run ./install.sh ghostty' >&2; exit 1; }
json="$(herdr session list --json)"
rows="$(jq -er '.sessions | if type != "array" then error("expected sessions array") else . end | map([.name, (if .running then "running" else "stopped" end)] | @tsv) | join("\n")' <<<"$json")"
names=(); i=0
while IFS=$'\t' read -r name status; do
  [ -n "$name" ] || continue
  names[$i]="$name"; i=$((i+1))
  printf '%2d) %s [%s]\n' "$i" "$name" "$status"
done <<<"$rows"
printf ' n) New named session\n q) Cancel\nChoose: '
IFS= read -r choice || exit 0
case "$choice" in
  q|Q|'') exit 0 ;;
  n|N)
    printf 'Session name (letters, numbers, dot, underscore, hyphen): '
    IFS= read -r name || exit 0
    case "$name" in ''|*[!a-zA-Z0-9._-]*) echo 'Invalid session name.' >&2; exit 1 ;; esac
    ;;
  *)
    case "$choice" in *[!0-9]*|'') echo 'Invalid selection.' >&2; exit 1 ;; esac
    # Avoid arithmetic overflow and octal parsing for user-entered numbers.
    [ "${#choice}" -le 6 ] || { echo 'Invalid selection.' >&2; exit 1; }
    idx=$((10#$choice))
    [ "$idx" -ge 1 ] && [ "$idx" -le "$i" ] || { echo 'Invalid selection.' >&2; exit 1; }
    name="${names[$((idx-1))]}"
    ;;
esac
exec herdr --session "$name"
