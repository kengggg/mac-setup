#!/usr/bin/env bash
#
# bootstrap.sh — zero-to-setup entry point for a brand-new Mac.
#
# If this repo is PUBLIC, run it with no prior checkout and no GitHub auth:
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
#
# The command-substitution form (not `curl | bash`) keeps your terminal as
# stdin, so interactive prompts (Homebrew, CLT) still work.
#
# It ensures git exists (Xcode CLT), clones the repo, and runs install.sh.
# Idempotent: re-running updates the checkout and re-runs the installer.

set -euo pipefail

REPO_URL="${MAC_SETUP_REPO:-https://github.com/kengggg/mac-setup.git}"
DEST="${MAC_SETUP_DEST:-$HOME/Workspaces/mac-setup}"

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }

# 1. Ensure git is available (Xcode Command Line Tools provide it).
if ! xcode-select -p >/dev/null 2>&1; then
  info "Installing Xcode Command Line Tools — accept the GUI dialog that appears…"
  xcode-select --install || true
  info "Waiting for Command Line Tools to finish…"
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

# 2. Clone or update the repo.
if [ -d "$DEST/.git" ]; then
  info "Updating existing checkout at $DEST"
  git -C "$DEST" pull --ff-only
else
  info "Cloning $REPO_URL -> $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi

# 3. Hand off to the idempotent installer (stdin is still the terminal here).
info "Running install.sh"
exec "$DEST/install.sh"
