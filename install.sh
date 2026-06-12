#!/usr/bin/env bash
#
# install.sh — component-based machine setup / resurrection.
#
# Usage:
#   ./install.sh                  # interactive menu: full / terminal-only / selective
#   ./install.sh --mode full      # everything
#   ./install.sh --mode minimal   # alacritty + zellij + nvim only (leaves shell alone)
#   ./install.sh --mode select    # interactive component checklist
#   ./install.sh alacritty nvim   # run specific components directly
#
# Components: alacritty  zellij  nvim  shell  devtools   (+ apps, macos in full)
# One-liner override:  MAC_SETUP_MODE=minimal /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
#
# Safe by design: never runs as root, backs up any existing file before
# linking, and every component is idempotent / re-runnable.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d%H%M%S)"
LOCAL="$HOME/.zshrc.local"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run install.sh as root." >&2
  exit 1
fi

# --- helpers ------------------------------------------------------------------

# back up an existing real file/dir, then symlink
link() {  # link <repo-relative-source> <absolute-destination>
  local src="$REPO/$1" dest="$2"
  mkdir -p "$(dirname "$dest")"
  if [ -L "$dest" ]; then
    ln -sfn "$src" "$dest"
  elif [ -e "$dest" ]; then
    mv "$dest" "$dest.bak-$TS"
    warn "backed up $dest -> $dest.bak-$TS"
    ln -sfn "$src" "$dest"
  else
    ln -sfn "$src" "$dest"
  fi
  log "linked $dest -> $src"
}

clone_if_absent() { [ -d "$2" ] || git clone --depth=1 "$1" "$2"; }

# idempotent brew install (handles formulae and casks)
brew_install() {
  local pkg
  for pkg in "$@"; do
    if brew list "$pkg" >/dev/null 2>&1 || brew list --cask "$pkg" >/dev/null 2>&1; then
      :
    else
      log "brew install $pkg"
      brew install "$pkg"
    fi
  done
}

# append a block to ~/.zshrc.local once, keyed by a unique marker (block on stdin)
ensure_local_block() {  # ensure_local_block <marker>
  local marker="$1" block
  block="$(cat)"
  touch "$LOCAL"
  grep -qF "$marker" "$LOCAL" && return 0
  printf '\n%s\n' "$block" >> "$LOCAL"
  log "added '$marker' to ~/.zshrc.local"
}

provision_nvim() {
  log "installing nvim plugins at locked versions (Lazy restore)"
  nvim --headless "+Lazy! restore" +qa || true
  log "provisioning treesitter parsers + Mason servers (this can take a while)"
  nvim --headless -c "luafile $REPO/scripts/nvim-provision.lua" -c "qa!" || true
}

# --- bootstrap (always runs first; everything needs Homebrew) -----------------
bootstrap_homebrew() {
  if ! command -v brew >/dev/null 2>&1; then
    log "installing Homebrew"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  else
    log "Homebrew already installed"
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
  if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    log "added brew shellenv to ~/.zprofile"
  fi
}

# --- components ---------------------------------------------------------------
comp_alacritty() {
  log "[alacritty]"
  brew_install alacritty font-meslo-lg-nerd-font
  link config/alacritty "$HOME/.config/alacritty"
}

comp_zellij() {
  log "[zellij]"
  brew_install zellij
  link config/zellij "$HOME/.config/zellij"
}

comp_nvim() {
  log "[nvim]"
  brew_install neovim ripgrep fd fzf tree-sitter-cli node
  link config/nvim "$HOME/.config/nvim"
  provision_nvim
}

comp_shell() {
  log "[shell]"
  if [ ! -d "$HOME/.oh-my-zsh" ]; then
    log "installing oh-my-zsh"
    RUNZSH=no KEEP_ZSHRC=yes CHSH=no \
      sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
  else
    log "oh-my-zsh already installed"
  fi
  local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
  clone_if_absent https://github.com/romkatv/powerlevel10k.git             "$custom/themes/powerlevel10k"
  clone_if_absent https://github.com/zsh-users/zsh-autosuggestions         "$custom/plugins/zsh-autosuggestions"
  clone_if_absent https://github.com/zsh-users/zsh-syntax-highlighting.git  "$custom/plugins/zsh-syntax-highlighting"
  brew_install fzf eza font-meslo-lg-nerd-font
  link home/zshrc    "$HOME/.zshrc"
  link home/p10k.zsh "$HOME/.p10k.zsh"
  link home/vimrc    "$HOME/.vimrc"
}

comp_devtools() {
  log "[devtools]"
  # Miniforge (conda + mamba) -> ~/miniforge3 (batch mode skips rc editing)
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

  # nvm + Node LTS (skip if any nvm already present)
  if [ ! -s "$HOME/.nvm/nvm.sh" ] && ! brew list nvm >/dev/null 2>&1; then
    log "installing nvm"; brew install nvm
  fi
  mkdir -p "$HOME/.nvm"
  ensure_local_block "export NVM_DIR=" <<'EOF'
export NVM_DIR="$HOME/.nvm"
[ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
EOF
  export NVM_DIR="$HOME/.nvm"
  if [ -s "$HOME/.nvm/nvm.sh" ]; then . "$HOME/.nvm/nvm.sh"
  elif [ -s "/opt/homebrew/opt/nvm/nvm.sh" ]; then . "/opt/homebrew/opt/nvm/nvm.sh"; fi
  if command -v nvm >/dev/null 2>&1 && ! nvm ls --no-colors 2>/dev/null | grep -qE 'v[0-9]'; then
    log "installing Node LTS via nvm"; nvm install --lts
  fi

  # Grok CLI
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
  # grok's installer may append its block to ~/.zshrc (our symlink); strip it
  # from the tracked repo file so the canonical block stays only in .zshrc.local.
  sed -i '' '/# >>> grok installer >>>/,/# <<< grok installer <<</d' "$REPO/home/zshrc" 2>/dev/null || true
}

comp_apps() {
  log "[apps] brew bundle (GUI apps + full package set)"
  brew bundle --file="$REPO/Brewfile"
}

comp_macos() {
  log "[macos] no system tweaks configured yet (edit comp_macos to add)"
}

run_component() {
  case "$1" in
    alacritty) comp_alacritty ;;
    zellij)    comp_zellij ;;
    nvim)      comp_nvim ;;
    shell)     comp_shell ;;
    devtools)  comp_devtools ;;
    apps)      comp_apps ;;
    macos)     comp_macos ;;
    *) echo "unknown component: $1" >&2; exit 1 ;;
  esac
}

# --- mode / component selection ----------------------------------------------
choose_mode() {  # sets MODE
  printf '\nSelect install mode:\n'
  printf '  1) full          — alacritty, zellij, nvim, shell, dev tools, apps\n'
  printf '  2) terminal-only — alacritty, zellij, nvim (leaves your shell alone)\n'
  printf '  3) selective     — choose components\n'
  printf 'Choice [1-3]: '
  local c; read -r c </dev/tty
  case "$c" in
    1) MODE=full ;;
    2) MODE=minimal ;;
    3) MODE=select ;;
    *) echo "invalid choice: $c" >&2; exit 1 ;;
  esac
}

choose_components() {  # sets COMPONENTS
  printf '\nSelect components by number (space-separated, e.g. "1 3"):\n'
  printf '  1) alacritty\n  2) zellij\n  3) nvim\n  4) shell\n  5) devtools\n'
  printf 'Components: '
  local nums n; read -r nums </dev/tty
  COMPONENTS=""
  for n in $nums; do
    case "$n" in
      1) COMPONENTS="$COMPONENTS alacritty" ;;
      2) COMPONENTS="$COMPONENTS zellij" ;;
      3) COMPONENTS="$COMPONENTS nvim" ;;
      4) COMPONENTS="$COMPONENTS shell" ;;
      5) COMPONENTS="$COMPONENTS devtools" ;;
      *) warn "ignoring invalid choice: $n" ;;
    esac
  done
}

# --- main ---------------------------------------------------------------------
MODE=""
ARGS=""
COMPONENTS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)   MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    -h|--help) sed -n '2,18p' "$0"; exit 0 ;;
    *) ARGS="$ARGS $1"; shift ;;
  esac
done
[ -z "$MODE" ] && MODE="${MAC_SETUP_MODE:-}"

if [ -n "$ARGS" ]; then
  COMPONENTS="$ARGS"                       # explicit component names win
else
  [ -z "$MODE" ] && choose_mode            # no mode given -> interactive menu
  case "$MODE" in
    full)                     COMPONENTS="alacritty zellij nvim shell devtools apps macos" ;;
    minimal|terminal|terminal-only) COMPONENTS="alacritty zellij nvim" ;;
    select|selective)         choose_components ;;
    *) echo "unknown mode: $MODE (use full|minimal|select)" >&2; exit 1 ;;
  esac
fi

if [ -z "${COMPONENTS// /}" ]; then
  warn "nothing selected; exiting"
  exit 0
fi

log "components:${COMPONENTS}"
bootstrap_homebrew
for c in $COMPONENTS; do run_component "$c"; done
log "done."
