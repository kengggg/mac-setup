#!/usr/bin/env bash
# Sourced by install.sh; only paired marker regions belong to the installer.
write_managed_file() (
  managed_file="$1" managed_replacement="$2"
  trap 'rm -f "$managed_replacement"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  cmp -s "$managed_file" "$managed_replacement" && exit 0
  # Check the entire resulting shell file before replacing any user data.
  /bin/zsh -n "$managed_replacement" || exit 1
  file_target "$managed_file" >/dev/null || exit 1
  if [ -e "$managed_file" ]; then
    [ -e "$managed_file.bak-$TS" ] || cp -p "$managed_file" "$managed_file.bak-$TS" || exit 1
  fi
  atomic_install_file "$managed_replacement" "$managed_file"
)

ensure_block() ( # managed_file, exact opening marker; replacement block on stdin
  managed_file="$1" managed_start="$2" managed_end='' managed_block='' managed_tmp=''
  trap 'rm -f "$managed_block" "$managed_tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' HUP TERM
  managed_end="${managed_start//>>>/<<<}"
  case "$managed_start" in '# >>> '*' >>>') ;; *) warn "invalid managed marker: $managed_start"; return 1 ;; esac
  managed_block="$(mktemp)"; cat > "$managed_block"
  mkdir -p "$(dirname "$managed_file")"
  managed_tmp="$(mktemp "${managed_file}.tmp.XXXXXX")"
  # Refuse duplicate, nested, or incomplete markers rather than eating user text.
  if ! awk -v managed_start="$managed_start" -v managed_end="$managed_end" -v managed_replacement="$managed_block" '
    function emit( line) { while ((getline line < managed_replacement) > 0) print line; close(managed_replacement) }
    $0 == managed_start { if (inside || count++) { bad=1; exit 1 }; inside=1; emit(); next }
    $0 == managed_end { if (!inside) { bad=1; exit 1 }; inside=0; next }
    !inside { print }
    END { if (bad || inside) exit 1; if (!count) { print ""; emit() } }
  ' "${managed_file:-/dev/null}" > "$managed_tmp" 2>/dev/null; then
    # A missing file is a fresh installation, not a malformed block.
    if [ ! -e "$managed_file" ] && [ ! -L "$managed_file" ]; then
      cat "$managed_block" > "$managed_tmp"
    else
      rm -f "$managed_tmp" "$managed_block"
      warn "malformed managed block in $managed_file ($managed_start); left unchanged"
      return 1
    fi
  fi
  rm -f "$managed_block"
  write_managed_file "$managed_file" "$managed_tmp"
)

migrate_legacy_nvm() {
  [ -f "$LOCAL" ] || return 0
  grep -qF '# >>> mac-setup nvm >>>' "$LOCAL" && return 0
  # Adopt only the exact three-line block emitted by older mac-setup versions.
  # Custom NVM initialization must remain handwritten and is never rewritten.
  local legacy tmp
  legacy="$(mktemp)"; tmp="$(mktemp "${LOCAL}.tmp.XXXXXX")"
  cat > "$legacy" <<'BLOCK'
export NVM_DIR="$HOME/.nvm"
[ -s "$HOME/.nvm/nvm.sh" ] && \. "$HOME/.nvm/nvm.sh"
[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"
BLOCK
  if ! awk -v legacy="$legacy" '
    BEGIN { while ((getline line < legacy)>0) expected[++n]=line; close(legacy) }
    { lines[NR]=$0 }
    END {
      for(i=1;i<=NR;i++) {
        if (lines[i] ~ /export NVM_DIR=/) {
          if (found++ || lines[i]!=expected[1] || lines[i+1]!=expected[2] || lines[i+2]!=expected[3]) exit 1
          print "# >>> mac-setup nvm >>>"
          print lines[i]; print lines[++i]; print lines[++i]
          print "# <<< mac-setup nvm <<<"
        } else print lines[i]
      }
    }
  ' "$LOCAL" > "$tmp"; then
    rm -f "$legacy" "$tmp"
    warn "custom NVM initialization in $LOCAL; wrap the intended block in mac-setup nvm markers before retrying devtools"
    return 1
  fi
  rm -f "$legacy"
  write_managed_file "$LOCAL" "$tmp"
}
