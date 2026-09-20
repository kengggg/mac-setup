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

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
fail() { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

# Where the clone lives: MAC_SETUP_DEST wins; else the pointer install.sh
# leaves at ~/.config/mac-setup/repo (so re-running this on a machine that
# keeps its clone elsewhere updates THAT clone instead of making a second
# one); else the default for a fresh machine. A pointer that no longer leads
# to a clone means the clone moved or was deleted — cloning the default path
# anyway would leave two clones and every managed link dangling, so stop and
# say what to do instead.
DEST="${MAC_SETUP_DEST:-}"
if [ -z "$DEST" ] && [ -L "$HOME/.config/mac-setup/repo" ]; then
  DEST="$(readlink "$HOME/.config/mac-setup/repo")"
  if [ -x "$DEST/install.sh" ]; then
    info "This machine keeps its clone at $DEST"
  else
    fail "the repo pointer ~/.config/mac-setup/repo -> $DEST no longer leads to a clone.
    - clone moved?   run ./install.sh relink from its new location, then re-run this
    - clone deleted? rm ~/.config/mac-setup/repo and re-run this to clone fresh
    - or set MAC_SETUP_DEST=/path/to/clone to override"
  fi
fi
DEST="${DEST:-$HOME/Workspaces/mac-setup}"

# 1. Ensure git is available (Xcode Command Line Tools provide it).
if ! xcode-select -p >/dev/null 2>&1; then
  info "Installing Xcode Command Line Tools — accept the GUI dialog that appears…"
  xcode-select --install || true
  info "Waiting for Command Line Tools to finish…"
  until xcode-select -p >/dev/null 2>&1; do sleep 5; done
fi

# 2. Clone or update the repo.
if [ -d "$DEST/.git" ]; then
  branch="$(git -C "$DEST" symbolic-ref --quiet --short HEAD 2>/dev/null || echo DETACHED)"
  info "Updating existing checkout at $DEST (branch=$branch)"
  [ "$branch" = main ] || info "This checkout follows $branch, not main; switch to main to receive merged changes."
  git -C "$DEST" pull --ff-only --no-rebase --autostash   # same flags as install.sh update
else
  info "Cloning $REPO_URL -> $DEST"
  mkdir -p "$(dirname "$DEST")"
  git clone "$REPO_URL" "$DEST"
fi

if [ -n "$(git -C "$DEST" ls-files -u)" ]; then
  fail "unresolved Git conflicts in $DEST; resolve them before running install.sh"
fi
info "Checkout commit: $(git -C "$DEST" rev-parse --short HEAD)"

# 3. Hand off to the idempotent installer (stdin is still the terminal here, so
#    its interactive mode menu works). Pass through any args; MAC_SETUP_MODE and
#    MAC_SETUP_COMPONENTS are inherited via the environment for unattended runs.
info "Running install.sh"
exec "$DEST/install.sh" "$@"
