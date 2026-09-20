#!/usr/bin/env bash
# Sourced by install.sh; only paired marker regions belong to the installer.
write_managed_file() {
  local file="$1" replacement="$2"
  if cmp -s "$file" "$replacement"; then rm -f "$replacement"; return 0; fi
  if [ -e "$file" ]; then
    [ -e "$file.bak-$TS" ] || cp -p "$file" "$file.bak-$TS"
    # Preserve file permissions and symlinks (including symlinked local config).
    cat "$replacement" > "$file"
    rm -f "$replacement"
  else
    mv "$replacement" "$file"
  fi
}

ensure_block() { # file, exact opening marker; replacement block on stdin
  local file="$1" start="$2" end block tmp
  end="${start//>>>/<<<}"
  case "$start" in '# >>> '*' >>>') ;; *) warn "invalid managed marker: $start"; return 1 ;; esac
  block="$(mktemp)"; cat > "$block"
  mkdir -p "$(dirname "$file")"
  tmp="$(mktemp "${file}.tmp.XXXXXX")"
  # Refuse duplicate, nested, or incomplete markers rather than eating user text.
  if ! awk -v start="$start" -v end="$end" -v replacement="$block" '
    function emit( line) { while ((getline line < replacement) > 0) print line; close(replacement) }
    $0 == start { if (inside || count++) { bad=1; exit 1 }; inside=1; emit(); next }
    $0 == end { if (!inside) { bad=1; exit 1 }; inside=0; next }
    !inside { print }
    END { if (bad || inside) exit 1; if (!count) { print ""; emit() } }
  ' "${file:-/dev/null}" > "$tmp" 2>/dev/null; then
    # A missing file is a fresh installation, not a malformed block.
    if [ ! -e "$file" ] && [ ! -L "$file" ]; then
      cat "$block" > "$tmp"
    else
      rm -f "$tmp" "$block"
      warn "malformed managed block in $file ($start); left unchanged"
      return 1
    fi
  fi
  rm -f "$block"
  write_managed_file "$file" "$tmp"
}

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
