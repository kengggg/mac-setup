#!/usr/bin/env bash
#
# install.sh — component-based machine setup / resurrection.
#
# Usage:
#   ./install.sh                  # interactive menu: full / partial
#   ./install.sh --mode full      # everything
#   ./install.sh --mode partial   # interactive component checklist
#   ./install.sh ghostty nvim     # run specific components directly
#   ./install.sh update           # git pull, then re-run this machine's recorded selection
#   ./install.sh doctor           # read-only health check of every managed link (+ git state)
#   ./install.sh relink           # repair links after moving the clone (no installs, no brew)
#
# Components: ghostty (Ghostty+herdr, Alacritty rescue)  nvim  shell  devtools  agents  apps  macos
# One-liner override:  MAC_SETUP_MODE=full /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
# Exact components (recorded like a partial run):
#   MAC_SETUP_COMPONENTS="ghostty nvim agents" /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
#
# Safe by design: never runs as root, backs up any existing file before
# linking, and every component is idempotent / re-runnable. Mode runs are
# recorded to ~/.config/mac-setup/selection so `update` can replay them.

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TS="$(date +%Y%m%d%H%M%S)"
LOCAL="$HOME/.zshrc.local"
STATE_FILE="$HOME/.config/mac-setup/selection"
# The machine's one pointer to its clone. Every managed dotfile links THROUGH
# this, so moving the clone invalidates one symlink instead of all of them,
# and any run from the new location repairs it (see ensure_repo_link).
REPO_LINK="$HOME/.config/mac-setup/repo"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }

if [ "$(id -u)" -eq 0 ]; then
  echo "Do not run install.sh as root." >&2
  exit 1
fi

# --- link layer -----------------------------------------------------------------
# The manifest: every dotfile this repo owns. Columns: component, repo-relative
# source, destination under $HOME. This is the ONLY place links are declared;
# components call link_component, relink/doctor walk the whole table.
links() {
  cat <<'EOF'
ghostty  config/ghostty                 .config/ghostty
ghostty  config/herdr/config.toml       .config/herdr/config.toml
ghostty  config/alacritty               .config/alacritty
nvim     config/nvim                    .config/nvim
shell    home/zshrc                     .zshrc
shell    home/p10k.zsh                  .p10k.zsh
shell    home/vimrc                     .vimrc
agents   claude/statusline-command.sh   .claude/statusline-command.sh
EOF
}

# Destinations that retired components used to link. The convergence pass
# deletes one only when it is a dangling symlink (the retired config dir is
# gone from the repo, so that link can never resolve); a real directory or a
# live link is someone's own and stays — doctor just calls it stale.
retired() {
  cat <<'EOF'
.config/zellij
EOF
}

# point $REPO_LINK at the clone this script runs from; say so if it moved
ensure_repo_link() {
  mkdir -p "$(dirname "$REPO_LINK")"
  if [ -L "$REPO_LINK" ]; then
    local cur; cur="$(readlink "$REPO_LINK")"
    if [ "$cur" != "$REPO" ]; then
      ln -sfn "$REPO" "$REPO_LINK"
      log "repo moved: $cur -> $REPO (updated $REPO_LINK)"
    fi
  elif [ -e "$REPO_LINK" ]; then
    mv "$REPO_LINK" "$REPO_LINK.bak-$TS"
    warn "backed up $REPO_LINK -> $REPO_LINK.bak-$TS"
    ln -sfn "$REPO" "$REPO_LINK"
  else
    ln -sfn "$REPO" "$REPO_LINK"
    log "repo pointer: $REPO_LINK -> $REPO"
  fi
}

# A symlink is ours when its target ends with the manifest's repo-relative
# path — true for links through the pointer AND for pre-pointer direct links
# into any clone, wherever it lived. Real files and other people's links
# never match.
is_ours() {  # is_ours <dest> <repo-relative-source>
  [ -L "$1" ] || return 1
  case "$(readlink "$1")" in */"$2") return 0 ;; esac
  return 1
}

# (re)point one link through the pointer; silent when already correct
set_link() {  # set_link <repo-relative-source> <absolute-destination>
  local want="$REPO_LINK/$1" dest="$2" verb="linked"
  [ "$(readlink "$dest" 2>/dev/null)" = "$want" ] && return 0
  [ -L "$dest" ] && verb="relinked"
  mkdir -p "$(dirname "$dest")"
  ln -sfn "$want" "$dest"
  log "$verb $dest -> $want"
}

# Unconditional pass, run at the start of EVERY install: adopt each managed
# link that is already ours (direct links from before the pointer existed,
# links left dangling by a moved clone). Never creates a link, never touches a
# real file or a foreign symlink — that stays gated by component selection.
converge_links() {
  local comp src dest
  while read -r comp src dest; do
    [ -n "$comp" ] || continue
    if is_ours "$HOME/$dest" "$src"; then set_link "$src" "$HOME/$dest"; fi
  done < <(links)
  while read -r dest; do
    [ -n "$dest" ] || continue
    if [ -L "$HOME/$dest" ] && [ ! -e "$HOME/$dest" ]; then
      rm "$HOME/$dest"
      log "removed dangling link of retired component: ~/$dest"
    fi
  done < <(retired)
  return 0
}

# Component-scoped: create the component's links, backing up any real file
# to name.bak-<timestamp> first (an existing symlink is simply replaced).
link_component() {  # link_component <component>
  local comp src dest d
  while read -r comp src dest; do
    [ "$comp" = "$1" ] || continue
    d="$HOME/$dest"
    if [ -e "$d" ] && [ ! -L "$d" ]; then
      mv "$d" "$d.bak-$TS"
      warn "backed up $d -> $d.bak-$TS"
    fi
    set_link "$src" "$d"
  done < <(links)
  return 0
}

# ~/.zprofile is a real file (never a link), so it can speak up when ~/.zshrc
# is a dead link — otherwise zsh silently starts with no config at all.
# Inert on machines whose ~/.zshrc is a real file or healthy.
ensure_zprofile_guard() {
  ensure_block "$HOME/.zprofile" "# >>> mac-setup guard >>>" <<'EOF'
# >>> mac-setup guard >>>
if [ -L "$HOME/.zshrc" ] && [ ! -e "$HOME/.zshrc" ]; then
  echo "mac-setup: ~/.zshrc is a broken link — the clone moved? (last known: $(readlink "$HOME/.config/mac-setup/repo" 2>/dev/null)). Run: <clone>/install.sh relink" >&2
fi
# <<< mac-setup guard <<<
EOF
}

# Read-only health report. Exit 1 only for what relink can fix (a dead pointer,
# a managed link that is broken or bypasses the pointer); foreign links, real
# files and not-installed components are informational.
doctor() {
  local bad=0 comp src dest d t want
  log "doctor"
  if [ -x "$REPO_LINK/install.sh" ]; then
    printf '    ok        repo pointer -> %s\n' "$(readlink "$REPO_LINK")"
  else
    printf '    BROKEN    repo pointer %s\n' "$REPO_LINK"; bad=1
  fi
  while read -r comp src dest; do
    [ -n "$comp" ] || continue
    d="$HOME/$dest"; want="$REPO_LINK/$src"
    if [ -L "$d" ]; then
      t="$(readlink "$d")"
      if [ "$t" = "$want" ] && [ -e "$d" ]; then
        printf '    ok        ~/%s\n' "$dest"
      elif is_ours "$d" "$src" && [ -e "$d" ]; then
        printf '    DIRECT    ~/%s -> %s (bypasses the repo pointer)\n' "$dest" "$t"; bad=1
      elif is_ours "$d" "$src"; then
        printf '    BROKEN    ~/%s -> %s\n' "$dest" "$t"; bad=1
      else
        printf '    foreign   ~/%s -> %s (not managed here)\n' "$dest" "$t"
      fi
    elif [ -e "$d" ]; then
      printf '    unmanaged ~/%s (real file; ./install.sh %s would adopt it)\n' "$dest" "$comp"
    else
      printf '    absent    ~/%s (%s not installed on this machine)\n' "$dest" "$comp"
    fi
  done < <(links)
  while read -r dest; do
    [ -n "$dest" ] || continue
    d="$HOME/$dest"
    if [ -L "$d" ] && [ ! -e "$d" ]; then
      printf '    BROKEN    ~/%s (retired component; relink removes it)\n' "$dest"; bad=1
    elif [ -e "$d" ]; then
      printf '    stale     ~/%s (retired component; yours to remove)\n' "$dest"
    fi
  done < <(retired)

  local dirty behind ahead counts
  dirty="$(git -C "$REPO" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  [ "$dirty" = 0 ] || warn "clone has $dirty uncommitted change(s): git -C $REPO status"
  counts="$(git -C "$REPO" rev-list --left-right --count '@{u}...HEAD' 2>/dev/null || true)"
  if [ -n "$counts" ]; then
    read -r behind ahead <<<"$counts"
    [ "$behind" = 0 ] || warn "clone is $behind commit(s) behind upstream (as of the last fetch): ./install.sh update"
    [ "$ahead" = 0 ]  || warn "clone is $ahead commit(s) ahead of upstream — push or reconcile"
  fi
  command -v herdr >/dev/null 2>&1 || warn "herdr not on PATH — Ghostty will fall back to plain zsh"

  if [ "$bad" -ne 0 ]; then
    warn "problems above are fixed by: $REPO/install.sh relink"
    return 1
  fi
  log "doctor: all managed links healthy"
}

# --- helpers ------------------------------------------------------------------

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

# record what this run installed so a later `./install.sh update` can replay
# it. Full runs are recorded by mode name (so components added to full later
# are picked up); partial runs record their exact component list.
save_selection() {
  mkdir -p "$(dirname "$STATE_FILE")"
  case "$MODE" in
    full)    printf 'mode=%s\n' "$MODE" > "$STATE_FILE" ;;
    partial) printf 'components=%s\n' "${COMPONENTS# }" > "$STATE_FILE" ;;
  esac
}

# append a block to a file once, keyed by a unique marker (block on stdin)
ensure_block() {  # ensure_block <file> <marker>
  local file="$1" marker="$2" block
  block="$(cat)"
  touch "$file"
  grep -qF "$marker" "$file" && return 0
  printf '\n%s\n' "$block" >> "$file"
  log "added '$marker' to ${file/#$HOME/~}"
}
ensure_local_block() { ensure_block "$LOCAL" "$1"; }  # ~/.zshrc.local shorthand

provision_nvim() {
  log "installing nvim plugins at locked versions (Lazy restore)"
  nvim --headless "+Lazy! restore" +qa || true
  log "provisioning treesitter parsers + Mason servers (this can take a while)"
  MAC_SETUP_PROVISION=1 nvim --headless -c "luafile $REPO/scripts/nvim-provision.lua" -c "qa!" || true
  echo   # the provision script's last write has no trailing newline
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
  # Fail fast if brew's prefix belongs to another user (e.g. the machine was
  # first set up under a different account) — every component needs brew, and
  # dying here with the fix beats dying mid-run on a random package.
  if [ ! -w /opt/homebrew ]; then
    warn "/opt/homebrew is not writable by $USER — brew installs will fail."
    warn "Fix once (from an admin account), then re-run:"
    warn "  sudo chown -R $USER /opt/homebrew"
    exit 1
  fi
  if ! grep -q 'brew shellenv' "$HOME/.zprofile" 2>/dev/null; then
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> "$HOME/.zprofile"
    log "added brew shellenv to ~/.zprofile"
  fi
}

# --- components ---------------------------------------------------------------
comp_ghostty() {
  log "[ghostty]"
  # Ghostty + herdr is the daily terminal (Ghostty's config auto-launches
  # herdr, falling back to plain zsh if it's missing). Alacritty is the
  # rescue terminal: plain login zsh, no multiplexer, its own config — a way
  # in when Ghostty, herdr or their configs misbehave. Installed together so
  # the rescue is always there.
  brew_install ghostty font-meslo-lg-nerd-font herdr alacritty
  # Arundina Sans Mono (Thai glyphs) has no brew cask; fetch TTFs from the
  # canonical TLWG release. Ghostty maps U+0E00-U+0E7F to it (see config).
  if ! ls "$HOME/Library/Fonts"/ArundinaSansMono* >/dev/null 2>&1; then
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL -o "$tmp/arundina.tar.xz" \
      "https://github.com/tlwg/fonts-arundina/releases/download/v0.4.0/ttf-arundina-0.4.0.tar.xz"
    tar -xJf "$tmp/arundina.tar.xz" -C "$tmp"
    cp "$tmp"/ttf-arundina-*/ArundinaSansMono*.ttf "$HOME/Library/Fonts/"
    rm -rf "$tmp"
    log "installed Arundina Sans Mono -> ~/Library/Fonts"
  fi
  # (herdr keeps runtime state — sockets, logs, session.json — in
  # ~/.config/herdr, so the manifest links only its config.toml, not the dir.)
  link_component ghostty
  # Cmd+Shift+M -> Window > Zoom (Ghostty's toggle_maximize is a no-op on
  # macOS; the native Zoom menu item is the Alacritty ToggleMaximized
  # equivalent). Applied at next Ghostty launch.
  defaults write com.mitchellh.ghostty NSUserKeyEquivalents -dict-add "Zoom" '@$m'
  # Ctrl+Cmd+drag anywhere in a window to move it — Ghostty's hidden
  # titlebar (macos-titlebar-style = hidden) leaves nothing to grab.
  # Global setting; apps pick it up on next launch.
  defaults write -g NSWindowShouldDragOnGesture -bool true
}

comp_nvim() {
  log "[nvim]"
  # imagemagick: snacks.nvim image rendering (non-PNG conversion)
  # mermaid-cli: mmdc, renders ```mermaid fences in markdown via snacks.image
  brew_install neovim ripgrep fd fzf tree-sitter-cli node lazygit imagemagick mermaid-cli
  # mermaid-cli's puppeteer needs a one-time headless-chrome download into
  # ~/.cache/puppeteer (exact version pinned by its bundled puppeteer-core;
  # without it mmdc fails with "Could not find chrome-headless-shell").
  local mc ver
  mc="$(brew --prefix)/opt/mermaid-cli/libexec/lib/node_modules/@mermaid-js/mermaid-cli/node_modules"
  ver="$(node -p "require('$mc/puppeteer-core/lib/puppeteer/revisions.js').PUPPETEER_REVISIONS['chrome-headless-shell']" 2>/dev/null || true)"
  if [ -n "$ver" ] && [ ! -d "$HOME/.cache/puppeteer/chrome-headless-shell/mac_arm-$ver" ]; then
    node "$mc/.bin/browsers" install "chrome-headless-shell@$ver" --path "$HOME/.cache/puppeteer"
  fi
  link_component nvim
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
  link_component shell

  # Machines with a two-account history can leave completion paths owned by
  # another user or group-writable; oh-my-zsh then prints a compaudit lecture
  # on EVERY shell start (which in turn trips p10k's instant-prompt warning).
  # Auto-fix what we can without sudo: chown fails even as root on symlink
  # targets inside app bundles (macOS App Management TCC), but the symlink's
  # own directory is ours — replace the link with a real, user-owned copy.
  # (probe ignores inherited FPATH — zsh defaults + brew's site-functions,
  # deterministically; brew shellenv's fpath line is zsh-only and does nothing
  # for this bash script)
  local audit='fpath+=(/opt/homebrew/share/zsh/site-functions); autoload -Uz compaudit && compaudit'
  local insecure p
  insecure="$(env -u FPATH zsh -fc "$audit" 2>/dev/null || true)"
  if [ -n "$insecure" ]; then
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      if [ -L "$p" ] && [ -w "$(dirname "$p")" ]; then
        cp -L "$p" "$p.tmp.$$" && chmod u+w,g-w,o-w "$p.tmp.$$" && mv "$p.tmp.$$" "$p"
        log "compaudit fix: replaced symlink with owned copy: $p"
      elif [ -O "$p" ]; then
        chmod g-w,o-w "$p" 2>/dev/null || true
        log "compaudit fix: tightened permissions: $p"
      fi
    done <<EOF
$insecure
EOF
    insecure="$(env -u FPATH zsh -fc "$audit" 2>/dev/null || true)"
    if [ -n "$insecure" ]; then
      warn "still-insecure completion paths remain (oh-my-zsh will warn on new shells):"
      printf '%s\n' "$insecure" >&2
      warn "these need manual attention (ownership by another user + macOS App"
      warn "Management can block even sudo chown; a brew reinstall of the owning"
      warn "app under this account usually clears it)"
    fi
  fi
}

comp_devtools() {
  log "[devtools]"
  # Miniforge (conda + mamba) -> ~/miniforge3 (batch mode skips rc editing)
  if [ ! -x "$HOME/miniforge3/bin/conda" ]; then
    log "installing Miniforge to ~/miniforge3"
    # the installer refuses to run unless its filename ends in .sh (its
    # "was I sourced?" heuristic), so don't hand it a bare mktemp file
    local tmp; tmp="$(mktemp -d)"
    curl -fsSL "https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-MacOSX-$(uname -m).sh" -o "$tmp/miniforge.sh"
    bash "$tmp/miniforge.sh" -b -p "$HOME/miniforge3"
    rm -rf "$tmp"
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
# Set MAMBA_ROOT_PREFIX before sourcing mamba.sh — otherwise mamba 2.0 prints
# warnings during shell init, which trips Powerlevel10k's instant prompt.
export MAMBA_ROOT_PREFIX="$HOME/miniforge3"
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

}

# Agent CLIs: Claude Code (+ statusline), Codex, Grok. Self-contained so a
# second machine can get them without devtools' conda/nvm.
comp_agents() {
  log "[agents]"
  brew_install jq codex                 # jq: statusline runtime dep; codex: Codex CLI

  # Claude Code — native installer puts the binary in ~/.local/bin, which the
  # tracked .zshrc already has on PATH.
  if command -v claude >/dev/null 2>&1 || [ -x "$HOME/.local/bin/claude" ]; then
    log "claude already installed"
  else
    log "installing Claude Code"
    curl -fsSL https://claude.ai/install.sh | bash
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

  # Claude Code statusline
  link_component agents
  # settings.json is Claude Code's own file — MERGE the statusLine key only,
  # never overwrite. Idempotent: skip if it already points at our script.
  local sj="$HOME/.claude/settings.json" cmd="bash ~/.claude/statusline-command.sh" tmp
  if [ -f "$sj" ]; then
    if [ "$(jq -r '.statusLine.command // ""' "$sj" 2>/dev/null)" = "$cmd" ]; then
      log "statusLine already set"
    else
      tmp="$(mktemp)"
      jq --arg c "$cmd" '.statusLine = {type:"command", command:$c}' "$sj" > "$tmp" && mv "$tmp" "$sj"
      log "merged statusLine into settings.json"
    fi
  else
    jq -n --arg c "$cmd" '{statusLine:{type:"command", command:$c}}' > "$sj"
    log "created settings.json with statusLine"
  fi
}

comp_apps() {
  log "[apps] brew bundle (GUI apps + full package set)"
  brew_install jq                       # used by the presence probe below
  # codexbar once lived in steipete/tap; it's now in homebrew/cask. A stale
  # tap shadows the official cask and trips brew's untrusted-tap guard in
  # non-interactive runs, so drop the tap first (nothing else is used from it).
  if brew tap 2>/dev/null | grep -q '^steipete/tap$'; then
    log "removing stale steipete/tap (codexbar now lives in homebrew/cask)"
    brew untap --force steipete/tap
  fi

  # Presence-based skip: an app that already exists in /Applications —
  # manually installed, App Store, or installed by another account — is left
  # alone. brew would otherwise treat it as uninstalled and re-attempt it on
  # EVERY run: re-downloading, then sudo-prompting to replace an app it may
  # not even own. Skipped apps keep updating themselves and stay outside brew.
  local skip="" managed casks tok app
  managed=" $(brew list --cask 2>/dev/null | tr '\n' ' ') "
  casks="$(sed -nE 's/^cask "([^"]+)".*/\1/p' "$REPO/Brewfile")"
  while IFS=$'\t' read -r tok app; do
    [ -n "$app" ] || continue
    case "$managed" in *" $tok "*) continue ;; esac   # brew-managed: bundle skips it itself
    if [ -e "/Applications/$app" ] || [ -e "$HOME/Applications/$app" ]; then
      skip="$skip $tok"
    fi
  done < <(brew info --cask --json=v2 $casks 2>/dev/null \
    | jq -r '.casks[] | .token as $t | (.artifacts[]? | select(.app?) | .app[0]? // empty) as $a | [$t, $a] | @tsv')
  # pkg-based casks expose no .app artifact (and their installers sudo) —
  # probe those from an explicit token:app table
  while IFS=: read -r tok app; do
    [ -n "$tok" ] || continue
    case "$managed" in *" $tok "*) continue ;; esac
    if [ -e "/Applications/$app" ]; then skip="$skip $tok"; fi
  done <<'EOF'
microsoft-office:Microsoft Word.app
tailscale-app:Tailscale.app
EOF
  if [ -n "$skip" ]; then
    log "leaving already-present apps alone:${skip}"
  fi

  # --no-upgrade: converge on missing packages only — upgrading what's already
  # installed is `brew upgrade`'s job, and a broken upgrade of an unrelated
  # cask (seen: a font cask whose files were deleted outside brew) must not
  # kill a setup run. Bundle errors are reported but non-fatal for the same
  # reason: one bad app shouldn't abort the remaining components.
  # (App Store apps are deliberately NOT installed — see the Brewfile.)
  if ! HOMEBREW_BUNDLE_CASK_SKIP="${skip# }" brew bundle install --no-upgrade --file="$REPO/Brewfile"; then
    warn "brew bundle finished with errors (see above) — fix and re-run: ./install.sh apps"
  fi
}

comp_macos() {
  log "[macos] system tweaks"
  # Ctrl+Cmd+drag anywhere inside a window to move it. Needed because Ghostty
  # runs with macos-titlebar-style = hidden — no titlebar to grab. Global for
  # all apps; takes effect for apps launched after the setting.
  defaults write -g NSWindowShouldDragOnGesture -bool true
  log "enabled Ctrl+Cmd+drag window moving (relaunch apps to pick it up)"
}

run_component() {
  case "$1" in
    ghostty)   comp_ghostty ;;
    alacritty) warn "alacritty is now part of the ghostty component (rescue terminal); running ghostty"; comp_ghostty ;;
    zellij)    warn "the zellij component was removed (herdr won the multiplexer trial); skipping" ;;
    nvim)      comp_nvim ;;
    shell)     comp_shell ;;
    devtools)  comp_devtools ;;
    agents)    comp_agents ;;
    claude)    warn "'claude' is now part of the 'agents' component; running agents"; comp_agents ;;
    apps)      comp_apps ;;
    macos)     comp_macos ;;
    *) echo "unknown component: $1" >&2; exit 1 ;;
  esac
}

# --- mode / component selection ----------------------------------------------
choose_mode() {  # sets MODE
  printf '\nSelect install mode:\n'
  printf '  1) full    — everything: terminals (ghostty+herdr, alacritty rescue), nvim, shell, dev tools, agent CLIs, apps, macOS tweaks\n'
  printf '  2) partial — choose components\n'
  printf 'Choice [1-2]: '
  local c; read -r c </dev/tty
  case "$c" in
    1) MODE=full ;;
    2) MODE=partial ;;
    *) echo "invalid choice: $c" >&2; exit 1 ;;
  esac
}

choose_components() {  # sets COMPONENTS
  printf '\nSelect components by number (space-separated, e.g. "1 3"):\n'
  printf '  1) ghostty   — Ghostty + herdr, and Alacritty as the plain rescue terminal\n'
  printf '  2) nvim      — Neovim + its tools, provisioned\n'
  printf '  3) shell     — oh-my-zsh, Powerlevel10k, plugins, .zshrc/.p10k.zsh/.vimrc\n'
  printf '  4) devtools  — Miniforge (conda), nvm + Node LTS\n'
  printf '  5) agents    — Claude Code + statusline, Codex, Grok\n'
  printf '  6) apps      — GUI apps from the Brewfile\n'
  printf '  7) macos     — system tweaks\n'
  printf 'Components: '
  local nums n; read -r nums </dev/tty
  COMPONENTS=""
  for n in $nums; do
    case "$n" in
      1) COMPONENTS="$COMPONENTS ghostty" ;;
      2) COMPONENTS="$COMPONENTS nvim" ;;
      3) COMPONENTS="$COMPONENTS shell" ;;
      4) COMPONENTS="$COMPONENTS devtools" ;;
      5) COMPONENTS="$COMPONENTS agents" ;;
      6) COMPONENTS="$COMPONENTS apps" ;;
      7) COMPONENTS="$COMPONENTS macos" ;;
      *) warn "ignoring invalid choice: $n" ;;
    esac
  done
}

# tests/link-layer.sh sources this file for its functions; stop before main
if [ -n "${MAC_SETUP_LIB:-}" ]; then return 0 2>/dev/null || exit 0; fi

# --- main ---------------------------------------------------------------------
MODE=""
ARGS=""
COMPONENTS=""
VERB=""
ORIG_ARGS=("$@")

while [ $# -gt 0 ]; do
  case "$1" in
    --mode)   MODE="${2:-}"; shift 2 ;;
    --mode=*) MODE="${1#*=}"; shift ;;
    -h|--help) sed -n '2,21p' "$0"; exit 0 ;;
    update) MODE="update"; shift ;;
    doctor|relink) VERB="$1"; shift ;;
    *) ARGS="$ARGS $1"; shift ;;
  esac
done
[ -z "$MODE" ] && MODE="${MAC_SETUP_MODE:-}"

# update: pull first, then hand over to the pulled install.sh. Bash reads a
# script as it runs, so the pull must not rewrite THIS process's file mid-flight
# — exec the fresh copy (flagged so it doesn't pull again). A failed pull
# (diverged clone, offline) warns and continues on the checked-out code.
if [ "$MODE" = "update" ] && [ -z "${MAC_SETUP_PULLED:-}" ]; then
  # --no-rebase: a pull.rebase=true config (tools set it) makes git refuse to
  # pull over ANY unstaged change; --autostash: nvim writes lazy-lock.json
  # through its symlink, so the clone is almost never clean.
  log "update: git pull --ff-only"
  if git -C "$REPO" pull --ff-only --no-rebase --autostash; then
    MAC_SETUP_PULLED=1 exec "$REPO/install.sh" "${ORIG_ARGS[@]}"
  else
    warn "pull failed — continuing with the code already checked out (git -C $REPO status)"
  fi
fi

# doctor is read-only; everything else first converges the machine onto the
# pointer scheme (idempotent, brew-free, independent of what was selected)
if [ "$VERB" = "doctor" ]; then
  if doctor; then exit 0; else exit 1; fi
fi
ensure_repo_link
converge_links
ensure_zprofile_guard
if [ "$VERB" = "relink" ]; then
  if doctor; then exit 0; else exit 1; fi
fi

# update: replay this machine's recorded selection (recorded by mode runs)
if [ "$MODE" = "update" ]; then
  MODE=""
  if [ -f "$STATE_FILE" ]; then
    SEL="$(cat "$STATE_FILE")"
    case "$SEL" in
      mode=full)    MODE=full ;;
      mode=*)       warn "recorded mode '${SEL#mode=}' is obsolete (modes are now full/partial) — choose again" ;;
      components=*) COMPONENTS="${SEL#components=}" ;;
      *) warn "unrecognized $STATE_FILE content; choose again" ;;
    esac
    if [ -n "$MODE$COMPONENTS" ]; then log "update: replaying recorded selection (${SEL})"; fi
  else
    warn "no recorded selection on this machine yet — choose one; it will be remembered"
  fi
fi

if [ -n "$ARGS" ]; then
  COMPONENTS="$ARGS"                       # explicit component names win
elif [ -z "$COMPONENTS" ]; then            # may already be set by `update` replay
  if [ -z "$MODE" ] && [ -n "${MAC_SETUP_COMPONENTS:-}" ]; then
    MODE=partial                           # recorded like a partial run
    COMPONENTS=" $MAC_SETUP_COMPONENTS"
  else
    [ -z "$MODE" ] && choose_mode          # no mode given -> interactive menu
    case "$MODE" in
      full)    COMPONENTS="ghostty nvim devtools shell agents apps macos" ;;
      partial) choose_components ;;
      *) echo "unknown mode: $MODE (use full|partial|update)" >&2; exit 1 ;;
    esac
  fi
fi

if [ -z "${COMPONENTS// /}" ]; then
  warn "nothing selected; exiting"
  exit 0
fi

log "components:${COMPONENTS}"
bootstrap_homebrew                           # fail-fast: everything needs brew

# One failing component must not abort the rest of the run. Each component
# executes in a subshell with its own set -e (so it still stops at its first
# internal error); failures are collected and summarized at the end.
FAILED=""
set +e
for c in $COMPONENTS; do
  ( set -e; run_component "$c" )
  if [ $? -ne 0 ]; then
    warn "[$c] failed — continuing with the remaining components"
    FAILED="$FAILED $c"
  fi
done
set -e

# record intent even with failures — `update` replays are idempotent and converge
if [ -z "$ARGS" ]; then save_selection; fi   # one-off component runs don't change the record

if [ -n "$FAILED" ]; then
  warn "components with errors:${FAILED} — fix above, then re-run: ./install.sh${FAILED}"
  exit 1
fi
doctor || exit 1                             # a run that leaves a managed link broken is not "done"
log "done."
