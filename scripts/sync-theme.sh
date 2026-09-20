#!/usr/bin/env bash
#
# sync-theme.sh — pull the lanna-tone theme from its canonical repo into this
# repo's configs. The theme's single source of truth is:
#     https://github.com/kengggg/lanna-tone-theme
#
# Run this whenever the theme changes, then review + commit the result:
#     ./scripts/sync-theme.sh && git diff
#
# The synced files stay tracked here, so mac-setup remains self-contained
# (no runtime dependency on the theme repo).

set -euo pipefail
RAW="https://raw.githubusercontent.com/kengggg/lanna-tone-theme/main/themes"
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

source "$REPO/scripts/filesystem.sh"

sync_themes() (
  stage='' ghostty='' alacritty='' changed=0 committed=0 old_ghostty=0 old_alacritty=0
  ghostty="$REPO/config/ghostty/themes/lanna-tone"
  alacritty="$REPO/config/alacritty/themes/lanna-tone.toml"
  # tomllib is needed only by this maintainer command, not the installer.
  python3 -c 'import tomllib' || { echo 'Theme sync requires Python 3.11 or newer.' >&2; exit 1; }
  stage="$(mktemp -d)" || exit 1
  finish_themes() {
    local rc=$? rollback_failed=0
    trap - EXIT HUP INT TERM
    if [ "$changed" -eq 1 ] && [ "$committed" -eq 0 ]; then
      if [ "$old_ghostty" -eq 1 ]; then
        atomic_install_file "$stage/old-ghostty" "$ghostty" || rollback_failed=1
      else rm -f "$ghostty" || rollback_failed=1; fi
      if [ "$old_alacritty" -eq 1 ]; then
        atomic_install_file "$stage/old-alacritty" "$alacritty" || rollback_failed=1
      else rm -f "$alacritty" || rollback_failed=1; fi
      if [ "$rollback_failed" -ne 0 ]; then
        echo "Theme rollback failed; original copies retained in $stage" >&2
        exit 1
      fi
      echo 'Theme sync failed; previous copies restored.' >&2
    fi
    rm -rf "$stage"
    exit "$rc"
  }
  trap finish_themes EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  log "syncing lanna-tone from kengggg/lanna-tone-theme"
  curl -fsSL "$RAW/ghostty.config" -o "$stage/ghostty" || exit 1
  curl -fsSL "$RAW/alacritty.toml" -o "$stage/alacritty" || exit 1
  python3 "$REPO/scripts/validate-themes.py" "$stage/ghostty" "$stage/alacritty" || exit 1
  mkdir -p "$(dirname "$ghostty")" "$(dirname "$alacritty")" || exit 1
  if [ -e "$ghostty" ]; then cp -p "$ghostty" "$stage/old-ghostty" || exit 1; old_ghostty=1; fi
  if [ -e "$alacritty" ]; then cp -p "$alacritty" "$stage/old-alacritty" || exit 1; old_alacritty=1; fi
  # Validate symlinks before promoting either file.
  file_target "$ghostty" >/dev/null && file_target "$alacritty" >/dev/null || exit 1
  changed=1
  atomic_install_file "$stage/ghostty" "$ghostty" || exit 1
  atomic_install_file "$stage/alacritty" "$alacritty" || exit 1
  committed=1
  log "updated both theme copies — review with 'git diff', then commit."
)

if [ "${MAC_SETUP_LIB:-}" != 1 ]; then sync_themes; fi
