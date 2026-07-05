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
curl -fsSL "$RAW/alacritty.toml" -o "$REPO/config/alacritty/themes/lanna-tone.toml"
log "updated config/alacritty/themes/lanna-tone.toml"
mkdir -p "$REPO/config/zellij/themes"
curl -fsSL "$RAW/zellij.kdl" -o "$REPO/config/zellij/themes/lanna-tone.kdl"
log "updated config/zellij/themes/lanna-tone.kdl"
log "done — review with 'git diff', then commit."
