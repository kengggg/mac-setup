#!/usr/bin/env bash
# Validate both before replacement and through the new pointer afterwards.
validate_checkout() {
  local root="$1" comp src dest path
  [ -x "$root/install.sh" ] && [ -f "$root/Brewfile" ] || return 1
  for path in install.sh scripts/filesystem.sh scripts/repo-pointer.sh \
      scripts/managed-block.sh scripts/doctor.sh scripts/herdr-session.sh; do
    [ -r "$root/$path" ] && /bin/bash -n "$root/$path" || return 1
  done
  for path in scripts/nvim-provision.lua config/nvim/init.lua config/nvim/lazy-lock.json \
      config/ghostty/config config/ghostty/themes/lanna-tone \
      config/alacritty/alacritty.toml config/alacritty/themes/lanna-tone.toml; do
    [ -s "$root/$path" ] || return 1
  done
  while read -r comp src dest; do
    [ -n "$comp" ] || continue
    [ -e "$root/$src" ] && [ -r "$root/$src" ] || return 1
  done < <(links)
}

replace_repo_pointer() (
  transaction='' old=absent changed=0 committed=0 backup="$REPO_LINK.bak-$TS"
  if [ ! -L "$REPO_LINK" ] && [ -d "$REPO_LINK" ] &&
     [ "$(cd "$REPO_LINK" && pwd -P)" = "$REPO" ]; then
    warn "the checkout occupies the reserved repo pointer path; move it elsewhere, then run ./install.sh relink"
    exit 1
  fi
  validate_checkout "$REPO" || { warn "incomplete or invalid checkout: $REPO; repo pointer left unchanged"; exit 1; }
  if [ -L "$REPO_LINK" ] && [ "$(readlink "$REPO_LINK")" = "$REPO" ]; then exit 0; fi
  mkdir -p "$(dirname "$REPO_LINK")" || exit 1
  transaction="$(mktemp -d "${REPO_LINK}.txn.XXXXXX")" || exit 1
  finish_pointer() {
    local rc=$?
    trap - EXIT HUP INT TERM
    if [ "$committed" -eq 0 ] && [ "$changed" -eq 1 ]; then
      case "$old" in
        link) atomic_rename "$transaction/previous" "$REPO_LINK" ;;
        real)
          # The backup may not exist if a signal arrived before mv completed.
          if [ -e "$backup" ]; then rm -f "$REPO_LINK" && mv "$backup" "$REPO_LINK"; fi
          ;;
        absent) rm -f "$REPO_LINK" ;;
      esac || { warn "pointer rollback failed; recovery files retained in $transaction and $backup"; exit 1; }
      warn "repo pointer restored after failed replacement"
    fi
    rm -rf "$transaction"
    exit "$rc"
  }
  trap finish_pointer EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  ln -s "$REPO" "$transaction/next" || exit 1
  if [ -L "$REPO_LINK" ]; then
    old=link
    ln -s "$(readlink "$REPO_LINK")" "$transaction/previous" || exit 1
  elif [ -e "$REPO_LINK" ]; then
    old=real
    [ ! -e "$backup" ] && [ ! -L "$backup" ] || { warn "backup already exists: $backup"; exit 1; }
    changed=1
    mv "$REPO_LINK" "$backup" || exit 1
  fi
  # Mark before rename so a signal immediately after it still rolls back.
  changed=1
  atomic_rename "$transaction/next" "$REPO_LINK" || exit 1
  [ "$(cd "$REPO_LINK" && pwd -P)" = "$REPO" ] && validate_checkout "$REPO_LINK" || exit 1
  committed=1
  if [ "$old" = real ]; then warn "backed up $REPO_LINK -> $backup"; fi
  if [ -n "${PREVIOUS_REPO:-}" ]; then
    log "repo moved: $PREVIOUS_REPO -> $REPO (updated $REPO_LINK)"
  else log "repo pointer: $REPO_LINK -> $REPO"; fi
)
