#!/usr/bin/env bash
# Sourced by install.sh. Reports local facts; never fetches, installs or sources
# the user's shell configuration. No record means link-only diagnostics.
repo_identity() {
  local branch commit
  branch="$(git -C "$REPO" symbolic-ref --quiet --short HEAD 2>/dev/null || echo DETACHED)"
  commit="$(git -C "$REPO" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  printf '    repo      branch=%s commit=%s\n' "$branch" "$commit"
  [ "$branch" = main ] || warn "checkout is on $branch; update follows this branch, not main"
}

# Bound native version/config probes so a misbehaving executable cannot hang doctor.
doctor_probe() {
  /usr/bin/perl -e 'my $seconds = shift @ARGV; alarm $seconds; exec @ARGV or die "exec failed: $!"' "${MAC_SETUP_PROBE_TIMEOUT:-15}" "$@"
}

doctor_command() {
  local name="$1" bin version
  bin="$(command -v "$name" 2>/dev/null || true)"
  if [ -z "$bin" ]; then
    case "$name" in
      ghostty) bin=/Applications/Ghostty.app/Contents/MacOS/ghostty ;;
      claude) bin="$HOME/.local/bin/claude" ;;
      grok) bin="$HOME/.grok/bin/grok" ;;
    esac
  fi
  if [ ! -x "$bin" ]; then
    printf '    MISSING   %s (retry: ./install.sh %s)\n' "$name" "$diagnostic_component"
    return 1
  fi
  if version="$(doctor_probe "$bin" --version 2>&1)"; then
    printf '    tool      %-14s %s [%s]\n' "$name" "$(printf '%s\n' "$version" | sed '/^WARNING:/d' | head -n 2 | tr '\n' ' ')" "$bin"
  else
    printf '    INVALID   %s version probe failed or timed out: %s\n' "$name" "$version"
    return 1
  fi
}

doctor_file() {
  if [ ! -e "$1" ]; then
    printf '    MISSING   %s (retry: ./install.sh %s)\n' "$1" "$diagnostic_component"
    return 1
  fi
}

doctor_toml() {
  # Python 3.11+ has a read-only TOML parser in the standard library.
  if command -v python3 >/dev/null && python3 -c 'import tomllib' 2>/dev/null; then
    python3 -c 'import sys,tomllib; tomllib.load(open(sys.argv[1], "rb"))' "$1" || return 1
    printf '    config    %s (TOML syntax ok)\n' "$1"
  else
    warn "UNCHECKED TOML syntax: $1 (Python 3.11+ not available)"
  fi
}

doctor_environment() {
  local selected="${COMPONENTS:-}" record diagnostic_component tool bad=0 output ghostty_bin inventory=""
  repo_identity
  if [ -z "$selected" ] && [ -f "$STATE_FILE" ]; then
    record="$(cat "$STATE_FILE")"
    case "$record" in
      mode=full) selected="$FULL_COMPONENTS" ;;
      components=*) selected="${record#components=}" ;;
      *) warn "unrecognized selection; run ./install.sh --mode partial"; return 1 ;;
    esac
  fi
  if [ -z "$selected" ]; then
    warn "no recorded components; dependency checks skipped (record a full/partial selection)"
    return 0
  fi
  printf '    selection %s\n' "$selected"
  # Include installed Homebrew versions for comparing reports between Macs.
  if command -v brew >/dev/null; then
    if inventory="$(HOMEBREW_NO_AUTO_UPDATE=1 brew list --versions 2>&1)"; then
      printf '    Homebrew versions for the curated Brewfile (no upgrades):\n'
      while read -r tool; do
        printf '%s\n' "$inventory" | awk -v tool="$tool" '$1 == tool { print "    brew      " $0 }'
      done < <(sed -nE 's/^(brew|cask) "([^"]+)".*/\2/p' "$REPO/Brewfile")
    else
      warn "could not read Homebrew inventory: $inventory"; bad=1
    fi
  else
    warn "Homebrew missing; run the selected components to install dependencies"; bad=1
  fi
  for diagnostic_component in $selected; do
    local commands=""
    case "$diagnostic_component" in
      ghostty|alacritty) commands="ghostty herdr jq" ;;
      nvim) commands="nvim rg fd fzf tree-sitter node deno lazygit magick mmdc" ;;
      shell) commands="zsh fzf eza" ;;
      agents|claude) commands="jq claude codex grok" ;;
      devtools) commands="" ;;
      apps) commands="gh mas" ;;
      macos) commands="" ;;
      zellij) warn "retired component: zellij"; continue ;;
      *) warn "unknown selected component: $diagnostic_component"; bad=1; continue ;;
    esac
    for tool in $commands; do doctor_command "$tool" || bad=1; done
    # A selected component must actually own its config links, not merely have
    # an unrelated real file at the same destination.
    local comp src dest expected="$diagnostic_component"
    [ "$expected" != alacritty ] || expected=ghostty
    [ "$expected" != claude ] || expected=agents
    while read -r comp src dest; do
      [ "$comp" = "$expected" ] || continue
      if [ ! -e "$HOME/$dest" ] || [ "$(readlink "$HOME/$dest" 2>/dev/null)" != "$REPO_LINK/$src" ]; then
        warn "selected $expected config not linked: ~/$dest — retry ./install.sh $expected"; bad=1
      fi
    done < <(links)
    case "$diagnostic_component" in
      ghostty|alacritty)
        ghostty_bin="$(command -v ghostty || true)"
        ghostty_bin="${ghostty_bin:-/Applications/Ghostty.app/Contents/MacOS/ghostty}"
        if [ -x "$ghostty_bin" ]; then
          if output="$(doctor_probe "$ghostty_bin" +validate-config 2>&1)"; then
            printf '    config    Ghostty validation passed\n'
            [ -z "$output" ] || printf '    note      %s\n' "$output"
          else warn "Ghostty config invalid: $output"; bad=1; fi
        fi
        doctor_toml "$HOME/.config/herdr/config.toml" || bad=1
        doctor_toml "$HOME/.config/alacritty/alacritty.toml" || bad=1
        [ -d /Applications/Alacritty.app ] || warn "Alacritty rescue app absent; its cask may require manual installation"
        ;;
      shell)
        for tool in "$HOME/.oh-my-zsh/oh-my-zsh.sh" \
          "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k/powerlevel10k.zsh-theme" \
          "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions/zsh-autosuggestions.plugin.zsh" \
          "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.plugin.zsh"; do
          doctor_file "$tool" || bad=1
        done
        for tool in "$HOME/.zshrc" "$HOME/.p10k.zsh" "$HOME/.zshrc.local" "$HOME/.zprofile"; do
          [ ! -f "$tool" ] || zsh -n "$tool" || bad=1
        done
        ;;
      nvim)
        if command -v nvim >/dev/null && [ -f "$HOME/.config/nvim/init.lua" ]; then
          MAC_SETUP_NVIM_CONFIG="$HOME/.config/nvim/init.lua" nvim --headless -u NONE -i NONE -n \
            -c 'lua local f,e=loadfile(vim.env.MAC_SETUP_NVIM_CONFIG); if not f then print(e); vim.cmd("cquit 1") end' -c 'qa!' || bad=1
        fi
        ;;
      devtools)
        if [ -x "$HOME/miniforge3/bin/conda" ]; then doctor_probe "$HOME/miniforge3/bin/conda" --version || bad=1
        else warn "Miniforge missing — retry ./install.sh devtools"; bad=1; fi
        local nvm_script="$HOME/.nvm/nvm.sh"
        [ -s "$nvm_script" ] || nvm_script=/opt/homebrew/opt/nvm/nvm.sh
        if [ -s "$nvm_script" ]; then
          doctor_probe bash --noprofile --norc -c 'export NVM_DIR="$HOME/.nvm"; . "$1"; printf "    nvm       "; nvm --version; printf "    node      "; nvm current; nvm version default' bash "$nvm_script" || bad=1
        else warn "nvm missing — retry ./install.sh devtools"; bad=1; fi
        ;;
      agents|claude)
        if command -v jq >/dev/null; then
          jq -e '.statusLine.command == "bash ~/.claude/statusline-command.sh"' "$HOME/.claude/settings.json" >/dev/null || {
            warn "Claude statusLine missing/invalid — retry ./install.sh agents"; bad=1;
          }
        fi
        ;;
      apps)
        if command -v brew >/dev/null; then
          while read -r tool; do
            if ! printf '%s\n' "$inventory" | awk -v tool="$tool" '$1 == tool { found=1 } END {exit !found}'; then
              warn "Brewfile formula missing: $tool — retry ./install.sh apps"; bad=1
            fi
          done < <(sed -nE 's/^brew "([^"]+)".*/\1/p' "$REPO/Brewfile")
          while read -r tool; do
            if ! printf '%s\n' "$inventory" | awk -v tool="$tool" '$1 == tool { found=1 } END {exit !found}'; then
              printf '    UNCHECKED %s is not brew-managed (may be installed manually); verify in Applications\n' "$tool"
            fi
          done < <(sed -nE 's/^cask "([^"]+)".*/\1/p' "$REPO/Brewfile")
        fi
        ;;
      macos)
        if [ "$(defaults read -g NSWindowShouldDragOnGesture 2>/dev/null || true)" != 1 ]; then
          warn "Ctrl+Cmd-drag preference missing — retry ./install.sh macos"; bad=1
        fi
        ;;
    esac
  done
  if [ "$bad" -eq 0 ]; then log "doctor: selected component checks passed (see any unchecked items above)"
  else warn "doctor: selected component checks failed; repair the items above"; fi
  return "$bad"
}
