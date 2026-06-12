#!/usr/bin/env bash
#
# install.sh — idempotent machine setup / resurrection.
#
# Usage:
#   ./install.sh              # run all steps in order
#   ./install.sh symlinks     # run only specific step(s)
#   ./install.sh brew nvim    # run several steps
#
# Steps: homebrew  brew  zsh  tools  symlinks  nvim  macos
#
# Safe by design: never runs as root, backs up any existing file before
# linking, and every step is re-runnable.

set -euo pipefail

# Resolve the repo root from this script's location (works wherever cloned).
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d%H%M%S)"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

# Refuse to run as root — we want files owned by the user.
if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run install.sh as root." >&2
  exit 1
fi

# --- symlink helper: back up an existing real file/dir, then link -------------
link() {  # link <repo-relative-source> <absolute-destination>
  local src="$REPO/$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest"                      # already a symlink: repoint
  elif [ -e "$dest" ]; then
    mv "$dest" "$dest.bak-$TS"                  # real file/dir: back up first
    warn "backed up $dest -> $dest.bak-$TS"
    ln -sfn "$src" "$dest"
  else
    ln -sfn "$src" "$dest"
  fi
  log "linked $dest -> $src"
}

clone_if_absent() { [ -d "$2" ] || git clone --depth=1 "$1" "$2"; }

# Machine-specific shell init lives in ~/.zshrc.local (untracked), sourced at
# the end of the shared .zshrc. Append a block once, keyed by a unique marker.
LOCAL="$HOME/.zshrc.local"
ensure_local_block() {  # ensure_local_block <marker>   (block text on stdin)
  local marker="$1" block
  block="$(cat)"
  touch "$LOCAL"
  grep -qF "$marker" "$LOCAL" && return 0
  printf '\n%s\n' "$block" >> "$LOCAL"
  log "added '$marker' to ~/.zshrc.local"
}

# --- steps --------------------------------------------------------------------
step_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    log "installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log "Homebrew already installed"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  # ensure future login shells get brew on PATH (~/.zprofile is machine-local,
  # not tracked in this repo, because the path differs per architecture)
  if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    log "added brew shellenv to ~/.zprofile"
  fi
}

step_brew() {
  log "brew bundle (installing CLI tools, fonts, casks)"
  brew bundle --file="$REPO/Brewfile"
}

step_zsh() {
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "installing oh-my-zsh"
    RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    log "oh-my-zsh already installed"
  fi
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  clone_if_absent https://github.com/romkatv/powerlevel10k.git            "$custom/themes/powerlevel10k"
  clone_if_absent https://github.com/zsh-users/zsh-autosuggestions        "$custom/plugins/zsh-autosuggestions"
  clone_if_absent https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/plugins/zsh-syntax-highlighting"
}

step_tools() {
  # --- Miniforge (conda + mamba) -> ~/miniforge3 (batch mode skips rc editing)
  if [ ! -x "$HOME/miniforge3/bin/conda" ]; then
    log "installing Miniforge to ~/miniforge3"
    local tmp; tmp="$(mktemp)"
    curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-$(uname -m).sh" -o "$tmp"
    bash "$tmp" -b -p "$HOME/miniforge3"
    rm -f "$tmp"
  else
    log "Miniforge already installed"
  fi
  ensure_local_block "# >>> conda initialize >>>" <<'EOF'
# >>> conda initialize >>>
__conda_setup="$("$HOME/miniforge3/bin/conda" 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "$HOME/miniforge3/etc/profile.d/conda.sh" ]; then
        . "$HOME/miniforge3/etc/profile.d/conda.sh"
    else
        export PATH="$HOME/miniforge3/bin:$PATH"
    fi
fi
unset __conda_setup
[ -f "$HOME/miniforge3/etc/profile.d/mamba.sh" ] && . "$HOME/miniforge3/etc/profile.d/mamba.sh"
# <<< conda initialize <<<
EOF

  # --- nvm + Node LTS (skip if any nvm already present)
  if [ ! -s "$HOME/.nvm/nvm.sh" ] && ! brew list nvm >/dev/null 2>&1; then
    log "installing nvm"; brew install nvm
  fi
  mkdir -p "$HOME/.nvm"
  ensure_local_block "export NVM_DIR=" <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
EOF
  # install Node LTS if nvm has no node yet
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh"
  elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then . "/opt/homebrew/opt/nvm/nvm.sh"; fi
  if command -v nvm >/dev/null 2>&1 && ! nvm ls --no-colors 2>/dev/null | grep -qE 'v[0-9]'; then
    log "installing Node LTS via nvm"; nvm install --lts
  fi

  # --- Grok CLI
  if [ ! -x "$HOME/.grok/bin/grok" ]; then
    log "installing grok CLI"
    curl -fsSL https://x.ai/cli/install.sh | bash
  else
    log "grok already installed"
  fi
  ensure_local_block "# >>> grok installer >>>" <<'EOF'
# >>> grok installer >>>
export PATH="$HOME/.grok/bin:$PATH"
fpath=(~/.grok/completions/zsh $fpath)
autoload -Uz compinit && compinit -C
# <<< grok installer <<<
EOF
  # grok's installer may append its block to ~/.zshrc; if that's our symlink,
  # the block lands in the tracked repo file. Strip it so the repo stays clean
  # (the canonical block lives in ~/.zshrc.local, added above).
  sed -i '' '/# >>> grok installer >>>/,/# <<< grok installer <<</d' "$REPO/home/zshrc" 2>/dev/null || true
}

step_symlinks() {
  log "linking config files (existing files are backed up)"
  link config/alacritty "$HOME/.config/alacritty"
  link config/zellij    "$HOME/.config/zellij"
  link config/nvim      "$HOME/.config/nvim"
  link home/zshrc       "$HOME/.zshrc"
  link home/p10k.zsh    "$HOME/.p10k.zsh"
  link home/vimrc       "$HOME/.vimrc"
}

step_nvim() {
  if ! command -v nvim >/dev/null 2>&1; then
    warn "nvim not installed yet — run the 'brew' step first; skipping"
    return 0
  fi
  log "installing nvim plugins at locked versions (Lazy restore)"
  nvim --headless "+Lazy! restore" +qa || true
  log "provisioning treesitter parsers + Mason servers (this can take a while)"
  nvim --headless -c "luafile $REPO/scripts/nvim-provision.lua" -c "qa!" || true
}

step_macos() {
  # Scaffold for future `defaults write` system tweaks. Nothing aggressive by
  # default. Example (commented):
  #   defaults write com.apple.dock autohide -bool true && killall Dock
  log "no macOS system tweaks configured yet (edit step_macos to add)"
}

# --- orchestration ------------------------------------------------------------
ALL_STEPS=(homebrew brew zsh tools symlinks nvim macos)

run_step() {
  case "$1" in
    homebrew) step_homebrew ;;
    brew)     step_brew ;;
    zsh)      step_zsh ;;
    tools)    step_tools ;;
    symlinks) step_symlinks ;;
    nvim)     step_nvim ;;
    macos)    step_macos ;;
    *) echo "unknown step: $1 (valid: ${ALL_STEPS[*]})" >&2; exit 1 ;;
  esac
}

main() {
  if [ "$#" -eq 0 ]; then
    for s in "${ALL_STEPS[@]}"; do run_step "$s"; done
  else
    for s in "$@"; do run_step "$s"; done
  fi
  log "done."
}

main "$@"
