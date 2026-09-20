#!/usr/bin/env bash
# No dependencies beyond macOS Bash. Only this reader touches the terminal;
# tests replace it with a scripted reader and never call installation commands.
menu_read() {
  if ! IFS= read -r REPLY </dev/tty; then
    echo 'A terminal is required. Use --mode full or component names for unattended setup.' >&2
    return 1
  fi
}

print_selection() {
  local group label item item_label
  while IFS='|' read -r group label; do
    contains_word "$COMPONENTS" "$group" || continue
    printf '  %s\n' "$label"
    while IFS='|' read -r item item_label; do
      [ -n "$item" ] || continue
      item_selected "$group" "$item" && printf '      %s\n' "$item_label"
    done < <(item_catalog "$group")
  done < <(component_catalog)
}
print_saved_selection() (
  if load_selection; then
    if [ "$MODE" = full ]; then printf 'Saved setup: everything\n'
    else printf 'Saved setup: custom choices\n'; fi
    printf 'Groups: %s\n' "$COMPONENTS"
  else printf 'No valid saved setup yet.\n'; fi
)

menu_main() {
  local choice
  while :; do
    printf '\nmac-setup\n\n'
    print_saved_selection
    printf '\n  1) Update saved setup (pull latest and apply)\n  2) Customize this Mac\n  3) Install everything\n  4) Check setup health\n  5) Repair configuration links\n  6) Reapply saved setup (no Git pull)\n  q) Quit\n\nChoice: '
    menu_read || return 1
    choice="$REPLY"
    case "$choice" in
      1|6)
        if ! (load_selection) >/dev/null 2>&1; then
          printf 'Choose Customize or Install everything to save a setup first.\n'; continue
        fi
        MODE=update
        [ "$choice" != 6 ] || REAPPLY=1
        return 0 ;;
      2) MODE=partial; return 0 ;;
      3) MODE=full; return 0 ;;
      4) VERB=doctor; return 0 ;;
      5) VERB=relink; return 0 ;;
      q|Q) return 2 ;;
      *) printf 'Choose 1–6 or q.\n' ;;
    esac
  done
}

menu_checklist() { # title, catalog; CHECKED in/out; 2=quit, 3=back
  local title="$1" catalog="$2" id label n token valid next selected_ids=''
  local ids=() labels=()
  while IFS='|' read -r id label; do
    [ -n "$id" ] || continue
    ids[${#ids[@]}]="$id"; labels[${#labels[@]}]="$label"
    if [ "$CHECKED" = '*' ] || contains_word "$CHECKED" "$id"; then selected_ids="${selected_ids:+$selected_ids }$id"; fi
  done <<< "$catalog"
  CHECKED="$selected_ids"
  while :; do
    printf '\n%s\n' "$title"
    for ((n=0; n<${#ids[@]}; n++)); do
      if contains_word "$CHECKED" "${ids[$n]}"; then label=x; else label=' '; fi
      printf '  %2d) [%s] %s\n' "$((n+1))" "$label" "${labels[$n]}"
    done
    printf '\nNumbers toggle choices (e.g. 1 3). all / none / back / q\nEnter = continue: '
    menu_read || return 1
    case "$REPLY" in
      '') return 0 ;;
      q|Q) return 2 ;;
      back|b) return 3 ;;
      all|a) CHECKED="${ids[*]}"; continue ;;
      none|n) CHECKED=''; continue ;;
    esac
    valid=1; selected_ids=''
    for token in $REPLY; do
      case "$token" in ''|*[!0-9]*) valid=0; break ;; esac
      # Match printed numbers as strings; avoid arithmetic overflow/octal input.
      id=''
      for ((n=0; n<${#ids[@]}; n++)); do
        [ "$token" != "$((n+1))" ] || id="${ids[$n]}"
      done
      [ -n "$id" ] || { valid=0; break; }
      contains_word "$selected_ids" "$id" || selected_ids="${selected_ids:+$selected_ids }$id"
    done
    if [ "$valid" = 0 ] || [ -z "$selected_ids" ]; then
      printf 'Invalid selection; nothing changed.\n'; continue
    fi
    for id in $selected_ids; do
      if contains_word "$CHECKED" "$id"; then
        next=''; for token in $CHECKED; do [ "$token" = "$id" ] || next="${next:+$next }$token"; done
        CHECKED="$next"
      else CHECKED="${CHECKED:+$CHECKED }$id"; fi
    done
  done
}

configure_setup() { # sets MODE, COMPONENTS, ITEMS_*; quit returns 2
  local group rc desired="$MODE" next
  if [ "$desired" = partial ]; then
    if ! load_selection; then COMPONENTS=''; reset_items; fi
    MODE=partial
  else COMPONENTS="$FULL_COMPONENTS"; reset_items; fi
  while :; do
    if [ "$MODE" = partial ]; then
      CHECKED="$COMPONENTS"
      rc=0; menu_checklist 'Choose installation groups' "$(component_catalog)" || rc=$?
      case "$rc" in 0) ;; 3) return 3 ;; *) return "$rc" ;; esac
      COMPONENTS="$CHECKED"
      [ -n "$COMPONENTS" ] || { printf 'Choose at least one group, or q to quit.\n'; continue; }
      rc=0
      for group in ghostty devtools agents apps; do
        contains_word "$COMPONENTS" "$group" || continue
        CHECKED="$(items_get "$group")"
        menu_checklist "Choose $group items" "$(item_catalog "$group")" || { rc=$?; break; }
        if [ -z "$CHECKED" ]; then
          next=''; for desired in $COMPONENTS; do [ "$desired" = "$group" ] || next="${next:+$next }$desired"; done
          COMPONENTS="$next"
        fi
        items_set "$group" "$CHECKED"
      done
      case "$rc" in 0) ;; 3) continue ;; *) return "$rc" ;; esac
      [ -n "$COMPONENTS" ] || { printf 'Nothing selected.\n'; continue; }
    fi
    printf '\nReview this Mac’s setup\n'
    print_selection
    printf '\nRequired dependencies are included. Unselected software is not uninstalled.\n'
    if [ "$MODE" = full ]; then printf 'Saved as: everything (future groups are included by update).\n'
    else printf 'Saved as: these exact groups and items for future updates.\n'; fi
    while :; do
      printf '\n  i) Install and save these choices\n  b) Back to choices\n  q) Quit without applying\nChoice: '
      menu_read || return 1
      case "$REPLY" in
        i|I) validate_selection; return $? ;;
        b|back) MODE=partial; break ;;
        q|Q) return 2 ;;
        *) printf 'Choose i, b, or q.\n' ;;
      esac
    done
  done
}

menu_start() {
  MENU_ACTION=1
  local rc
  while :; do
    MODE='' VERB='' COMPONENTS='' REAPPLY=0
    rc=0; menu_main || rc=$?
    [ "$rc" = 0 ] || return "$rc"
    case "$MODE" in
      full|partial)
        rc=0; configure_setup || rc=$?
        case "$rc" in 3) continue ;; 0) SETUP_READY=1 ;; *) return "$rc" ;; esac
        ;;
    esac
    return 0
  done
}
