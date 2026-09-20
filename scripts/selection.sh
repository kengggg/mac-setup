#!/usr/bin/env bash
# Selection data is parsed, never sourced. Unset item lists mean the whole group.
reset_items() { ITEMS_GHOSTTY='*'; ITEMS_DEVTOOLS='*'; ITEMS_AGENTS='*'; ITEMS_APPS='*'; }
reset_items

component_catalog() {
  cat <<'LIST'
ghostty|Terminals — Ghostty, herdr, Alacritty
nvim|Neovim — editor, plugins and required tools
shell|Shell — zsh, Powerlevel10k and required plugins
devtools|Development runtimes — Miniforge, nvm + Node
agents|Agent CLIs — Claude Code, Codex, Grok
apps|Brewfile apps & tools — packages only
macos|macOS — Ctrl+Cmd-drag window moving
LIST
}

item_catalog() {
  case "$1" in
    ghostty) printf '%s\n' 'ghostty|Ghostty + fonts (plain login zsh)' 'herdr|herdr + jq (manual sessions)' 'alacritty|Alacritty + font (rescue terminal)' ;;
    devtools) printf '%s\n' 'miniforge|Miniforge (conda + mamba)' 'nvm|nvm + Node LTS' ;;
    agents) printf '%s\n' 'claude|Claude Code + statusline' 'codex|Codex CLI' 'grok|Grok CLI' ;;
    apps) awk -F '"' '/^(brew|cask) "/ {kind=($0 ~ /^brew / ? "brew" : "cask"); print kind ":" $2 "|" $2 " (" (kind=="brew" ? "tool" : "app/font") ")"}' "$REPO/Brewfile" ;;
  esac
}

items_get() {
  case "$1" in
    ghostty) printf '%s' "$ITEMS_GHOSTTY" ;;
    devtools) printf '%s' "$ITEMS_DEVTOOLS" ;;
    agents) printf '%s' "$ITEMS_AGENTS" ;;
    apps) printf '%s' "$ITEMS_APPS" ;;
    *) printf '*' ;;
  esac
}
items_set() {
  case "$1" in
    ghostty) ITEMS_GHOSTTY="$2" ;;
    devtools) ITEMS_DEVTOOLS="$2" ;;
    agents) ITEMS_AGENTS="$2" ;;
    apps) ITEMS_APPS="$2" ;;
    *) return 1 ;;
  esac
}
contains_word() { case " $1 " in *" $2 "*) return 0 ;; *) return 1 ;; esac; }
item_selected() { local chosen; chosen="$(items_get "$1")"; [ "$chosen" = '*' ] || contains_word "$chosen" "$2"; }
source_selected() {
  case "$1:$2" in
    ghostty:config/ghostty) item_selected ghostty ghostty ;;
    ghostty:config/herdr/config.toml) item_selected ghostty herdr ;;
    ghostty:config/alacritty) item_selected ghostty alacritty ;;
    agents:*) item_selected agents claude ;;
    *) return 0 ;;
  esac
}

normalize_components() { # sets COMPONENTS; also validates CLI/recorded values
  local component normalized=''
  for component in $COMPONENTS; do
    case "$component" in
      claude) component=agents ;;
      alacritty) component=ghostty ;;
      zellij) warn 'retired component: zellij; skipping' >&2; continue ;;
      ghostty|nvim|shell|devtools|agents|apps|macos) ;;
      *) warn "unknown component: $component" >&2; return 1 ;;
    esac
    contains_word "$normalized" "$component" || normalized="${normalized:+$normalized }$component"
  done
  COMPONENTS="$normalized"
}
validate_selection() {
  normalize_components || return 1
  local group chosen allowed item normalized
  for group in ghostty devtools agents apps; do
    chosen="$(items_get "$group")"
    [ "$chosen" != '*' ] || continue
    allowed="$(item_catalog "$group" | cut -d '|' -f 1 | tr '\n' ' ')"
    normalized=''
    for item in $chosen; do
      contains_word "$allowed" "$item" || { warn "unknown $group item: $item" >&2; return 1; }
      contains_word "$normalized" "$item" || normalized="${normalized:+$normalized }$item"
    done
    if contains_word "$COMPONENTS" "$group" && [ -z "$normalized" ]; then
      warn "no items selected for $group" >&2; return 1
    fi
    items_set "$group" "$normalized"
  done
}

load_selection() { # legacy one-line records and detailed version 2 records
  [ -f "$STATE_FILE" ] || return 1
  local line key value seen='' version='' selection_kind=''
  MODE='' COMPONENTS=''; reset_items
  while IFS= read -r line || [ -n "$line" ]; do
    key="${line%%=*}"; value="${line#*=}"
    [ "$key" != "$line" ] && ! contains_word "$seen" "$key" || return 1
    seen="$seen $key"
    case "$key" in
      version) [ "$value" = 2 ] || return 1; version=2 ;;
      mode) [ "$value" = full ] && [ -z "$selection_kind" ] || return 1
        MODE=full; COMPONENTS="$FULL_COMPONENTS"; selection_kind=full ;;
      components) [ -n "$value" ] && [ -z "$selection_kind" ] || return 1
        MODE=partial; COMPONENTS="$value"; selection_kind=partial ;;
      items.ghostty|items.devtools|items.agents|items.apps) items_set "${key#items.}" "$value" ;;
      *) return 1 ;;
    esac
  done < "$STATE_FILE"
  [ -n "$selection_kind" ] || return 1
  case "$seen" in *items.*) [ "$version" = 2 ] && [ "$MODE" = partial ] || return 1 ;; esac
  validate_selection
}

save_selection() (
  [ "$MODE" = full ] || [ "$MODE" = partial ] || exit 0
  mkdir -p "$(dirname "$STATE_FILE")" || exit 1
  selection_tmp="$(mktemp "${STATE_FILE}.tmp.XXXXXX")" || exit 1
  trap 'rm -f "$selection_tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  if [ "$MODE" = full ]; then
    printf 'mode=full\n' > "$selection_tmp"
  else
    detailed=0
    for group in ghostty devtools agents apps; do
      if contains_word "$COMPONENTS" "$group" && [ "$(items_get "$group")" != '*' ]; then detailed=1; fi
    done
    [ "$detailed" = 0 ] || printf 'version=2\n' > "$selection_tmp"
    printf 'components=%s\n' "$COMPONENTS" >> "$selection_tmp"
    for group in ghostty devtools agents apps; do
      if contains_word "$COMPONENTS" "$group" && [ "$(items_get "$group")" != '*' ]; then
        printf 'items.%s=%s\n' "$group" "$(items_get "$group")" >> "$selection_tmp"
      fi
    done
  fi
  atomic_install_file "$selection_tmp" "$STATE_FILE"
)

apps_brewfile() { # preserve the curated Ruby declarations, including adopt flags
  if [ "$ITEMS_APPS" = '*' ]; then cat "$REPO/Brewfile"; return; fi
  awk -F '"' -v selected=" $ITEMS_APPS " '/^(brew|cask) "/ {
    kind=($0 ~ /^brew / ? "brew" : "cask")
    if (index(selected, " " kind ":" $2 " ")) print
  }' "$REPO/Brewfile"
}

retry_command() {
  if [ "$(items_get "$1")" = '*' ]; then printf './install.sh %s' "$1"
  else printf './install.sh reapply'; fi
}
