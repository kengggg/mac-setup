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
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

log "syncing lanna-tone from kengggg/lanna-tone-theme"
mkdir -p "$REPO/config/ghostty/themes"
curl -fsSL "$RAW/ghostty.config" -o "$REPO/config/ghostty/themes/lanna-tone"
log "updated config/ghostty/themes/lanna-tone"
log "done — review with 'git diff', then commit."
