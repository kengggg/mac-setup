#!/usr/bin/env bash
# Shared file operations. Staging lives on the destination filesystem.
# Transaction functions use subshell-scoped variables, not local: Bash 3.2
# unwinds function locals before running a subshell EXIT trap.
atomic_rename() {
  # Unlike mv, rename does not follow a destination symlink to a directory.
  /usr/bin/perl -e 'rename $ARGV[0], $ARGV[1] or die "rename: $!\n"' -- "$1" "$2"
}

file_target() { # Resolve a file's symlink chain without replacing the links.
  local path="$1" target parent count=0
  while :; do
    parent="$(cd "$(dirname "$path")" && pwd -P)" || return 1
    path="$parent/$(basename "$path")"
    [ -L "$path" ] || break
    count=$((count+1))
    [ "$count" -le 40 ] || { echo "symlink loop: $1" >&2; return 1; }
    target="$(readlink "$path")" || return 1
    case "$target" in /*) path="$target" ;; *) path="$(dirname "$path")/$target" ;; esac
    [ -e "$path" ] || [ -L "$path" ] || { echo "dangling symlink: $1" >&2; return 1; }
  done
  [ ! -e "$path" ] || [ -f "$path" ] || { echo "not a regular file: $path" >&2; return 1; }
  printf '%s\n' "$path"
}

atomic_install_file() ( # source, destination; preserve existing permissions/links
  atomic_target='' atomic_stage=''
  atomic_target="$(file_target "$2")" || exit 1
  trap 'rm -f "$atomic_stage"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM HUP
  atomic_stage="$(mktemp "${atomic_target}.tmp.XXXXXX")" || exit 1
  if [ -e "$atomic_target" ]; then cp -p "$atomic_target" "$atomic_stage" || exit 1; fi
  cat "$1" > "$atomic_stage" || exit 1
  atomic_rename "$atomic_stage" "$atomic_target"
)
