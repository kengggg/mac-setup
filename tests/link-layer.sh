#!/usr/bin/env bash
#
# tests/link-layer.sh — exercises install.sh's link layer against a throwaway
# $HOME and a local bare git remote. Nothing here touches the real machine:
# no brew, no network, no component installs.
#
#   ./tests/link-layer.sh          # run all
#   ./tests/link-layer.sh t_name   # run one
#
# Each case gets a fresh sandbox: $SB/home (fake $HOME), $SB/origin.git (bare
# remote built from THIS working tree, uncommitted changes included) and
# $SB/a (a clone of it). Cases that need a second clone make $SB/b.

set -uo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPROOT="${TMPDIR:-/tmp}"; TMPROOT="${TMPROOT%/}/mac-setup-tests.$$"
PASS=0; FAIL=0; FAILED=""

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }

# --- sandbox -------------------------------------------------------------------
make_origin() {  # one bare remote per run, built from the working tree
  ORIGIN="$TMPROOT/origin.git"
  [ -d "$ORIGIN" ] && return 0
  local stage="$TMPROOT/stage"
  mkdir -p "$TMPROOT"
  rsync -a --exclude .git --exclude backend "$SRC/" "$stage/"
  git -C "$stage" init -q -b main
  git -C "$stage" -c user.name=t -c user.email=t@t add -A
  git -C "$stage" -c user.name=t -c user.email=t@t commit -q -m "working tree"
  git clone -q --bare "$stage" "$ORIGIN"
}

sandbox() {  # sandbox <name>  -> sets SB, HOME, A
  make_origin
  SB="$TMPROOT/$1"; rm -rf "$SB"; mkdir -p "$SB/home"
  git clone -q "$ORIGIN" "$SB/a"
  A="$SB/a"
  export HOME="$SB/home"
}

# link <dest-under-home> <target>  (old-scheme direct link)
mklink() { mkdir -p "$(dirname "$HOME/$1")"; ln -sfn "$2" "$HOME/$1"; }

# --- assertions ---------------------------------------------------------------
_fail() { red "    FAIL: $*"; return 1; }

assert_resolves() {  # <dest-under-home> <expected-real-path>
  local d="$HOME/$1" want="$2" got
  [ -e "$d" ] || _fail "$1 does not resolve (target: $(readlink "$d" 2>/dev/null || echo none))" || return 1
  got="$(cd "$(dirname "$d")" && python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$d")"
  want="$(python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$want")"
  [ "$got" = "$want" ] || _fail "$1 resolves to $got, want $want"
}
assert_via_pointer() {  # <dest-under-home> <repo-relative-src>
  local t; t="$(readlink "$HOME/$1")"
  [ "$t" = "$HOME/.config/mac-setup/repo/$2" ] || _fail "$1 -> $t (want via pointer: \$HOME/.config/mac-setup/repo/$2)"
}
assert_link_target() {  # <dest-under-home> <exact target>
  local t; t="$(readlink "$HOME/$1")"
  [ "$t" = "$2" ] || _fail "$1 -> $t, want $2"
}
assert_regular_file() { [ -f "$HOME/$1" ] && [ ! -L "$HOME/$1" ] || _fail "$1 is not a regular file"; }
assert_no_glob()  { local m; m=$(compgen -G "$HOME/$1" || true); [ -z "$m" ] || _fail "unexpected: $m"; }
assert_contains() { grep -qF -- "$2" <<<"$1" || _fail "output lacks '$2':"$'\n'"$1"; }
assert_lacks()    { ! grep -qF -- "$2" <<<"$1" || _fail "output has '$2':"$'\n'"$1"; }
assert_count()    { local n; n=$(grep -cF -- "$2" "$1"); [ "$n" = "$3" ] || _fail "$1 has $n x '$2', want $3"; }
assert_eq()       { [ "$1" = "$2" ] || _fail "got '$1', want '$2'"; }

# --- cases --------------------------------------------------------------------

t_relink_adopts_old_direct_links() {
  sandbox old
  mklink .zshrc     "$A/home/zshrc"
  mklink .p10k.zsh  "$A/home/p10k.zsh"
  mklink .vimrc     "$A/home/vimrc"
  mklink .config/ghostty "$A/config/ghostty"
  mklink .config/herdr/config.toml "$A/config/herdr/config.toml"
  mklink .config/nvim "$A/config/nvim"
  mklink .claude/statusline-command.sh "$A/claude/statusline-command.sh"
  "$A/install.sh" relink >/dev/null 2>&1 || _fail "relink exited $?" || return 1
  assert_link_target .config/mac-setup/repo "$A" &&
  assert_via_pointer .zshrc home/zshrc &&
  assert_via_pointer .config/ghostty config/ghostty &&
  assert_via_pointer .config/herdr/config.toml config/herdr/config.toml &&
  assert_via_pointer .claude/statusline-command.sh claude/statusline-command.sh &&
  assert_resolves .zshrc "$A/home/zshrc" &&
  assert_resolves .config/nvim "$A/config/nvim"
}

t_relink_repairs_after_clone_moved() {
  sandbox moved
  mklink .zshrc "$A/home/zshrc"
  mklink .config/ghostty "$A/config/ghostty"
  "$A/install.sh" relink >/dev/null 2>&1
  mv "$A" "$SB/b"
  [ -e "$HOME/.zshrc" ] && { _fail "precondition: .zshrc should dangle after move"; return 1; }
  local out; out="$("$SB/b/install.sh" relink 2>&1)" || _fail "relink exited $?: $out" || return 1
  assert_contains "$out" "repo moved" &&
  assert_link_target .config/mac-setup/repo "$SB/b" &&
  assert_resolves .zshrc "$SB/b/home/zshrc" &&
  assert_resolves .config/ghostty "$SB/b/config/ghostty"
}

t_relink_leaves_real_files_alone() {
  sandbox realfile
  printf 'mine\n' > "$HOME/.zshrc"
  "$A/install.sh" relink >/dev/null 2>&1
  assert_regular_file .zshrc &&
  assert_eq "$(cat "$HOME/.zshrc")" "mine" &&
  assert_no_glob ".zshrc.bak-*"
}

t_relink_leaves_foreign_links_alone() {
  sandbox foreign
  mkdir -p "$HOME/dotfiles"; printf 'theirs\n' > "$HOME/dotfiles/vimrc"
  mklink .vimrc "$HOME/dotfiles/vimrc"
  mklink .zshrc "$HOME/gone/zshrc"            # dangling AND foreign: still not ours
  "$A/install.sh" relink >/dev/null 2>&1
  assert_link_target .vimrc "$HOME/dotfiles/vimrc" &&
  assert_link_target .zshrc "$HOME/gone/zshrc"
}

t_relink_is_idempotent() {
  sandbox idem
  mklink .zshrc "$A/home/zshrc"
  "$A/install.sh" relink >/dev/null 2>&1
  local out; out="$("$A/install.sh" relink 2>&1)"
  assert_lacks "$out" "relinked" &&
  assert_lacks "$out" "repo moved" &&
  assert_count "$HOME/.zprofile" ">>> mac-setup guard >>>" 1
}

t_link_component_creates_links_on_fresh_home() {
  sandbox fresh
  ( cd "$A" && MAC_SETUP_LIB=1 . ./install.sh && ensure_repo_link >/dev/null && link_component shell >/dev/null ) || return 1
  assert_via_pointer .zshrc home/zshrc &&
  assert_via_pointer .p10k.zsh home/p10k.zsh &&
  assert_via_pointer .vimrc home/vimrc &&
  assert_resolves .p10k.zsh "$A/home/p10k.zsh" &&
  [ ! -e "$HOME/.config/ghostty" ] || _fail "shell component must not create ghostty links"
}

t_link_component_backs_up_real_file() {
  sandbox backup
  printf 'mine\n' > "$HOME/.zshrc"
  ( cd "$A" && MAC_SETUP_LIB=1 . ./install.sh && ensure_repo_link >/dev/null && link_component shell >/dev/null 2>&1 ) || return 1
  assert_via_pointer .zshrc home/zshrc &&
  [ -n "$(compgen -G "$HOME/.zshrc.bak-*")" ] || _fail "no backup of the real .zshrc"
}

t_zprofile_guard_speaks_only_when_zshrc_dangles() {
  sandbox guard
  mklink .zshrc "$A/home/zshrc"
  "$A/install.sh" relink >/dev/null 2>&1
  local quiet loud
  quiet="$(zsh -c 'source "$HOME/.zprofile"' 2>&1)"
  mv "$A" "$SB/b"
  loud="$(zsh -c 'source "$HOME/.zprofile"' 2>&1)"
  assert_eq "$quiet" "" &&
  assert_contains "$loud" "mac-setup" &&
  assert_contains "$loud" "relink"
}

t_doctor_exit_codes() {
  sandbox doctor
  mklink .zshrc "$A/home/zshrc"
  "$A/install.sh" relink >/dev/null 2>&1
  "$A/install.sh" doctor >/dev/null 2>&1 || _fail "doctor should pass on a healthy home (exit $?)" || return 1
  mv "$A" "$SB/b"
  local out; out="$("$SB/b/install.sh" doctor 2>&1)"; local rc=$?
  assert_eq "$rc" "1" &&
  assert_contains "$out" ".zshrc" &&
  assert_contains "$out" "relink"
}

t_doctor_reports_unmanaged_without_failing() {
  sandbox unmanaged
  mkdir -p "$HOME/dotfiles"; : > "$HOME/dotfiles/vimrc"
  mklink .vimrc "$HOME/dotfiles/vimrc"
  printf 'mine\n' > "$HOME/.zshrc"
  "$A/install.sh" relink >/dev/null 2>&1
  local out; out="$("$A/install.sh" doctor 2>&1)"; local rc=$?
  assert_eq "$rc" "0" &&
  assert_contains "$out" ".vimrc" &&
  assert_contains "$out" ".zshrc"
}

t_update_pulls_then_runs_new_code() {
  sandbox update
  # publish a new install.sh that proves it is the one running, then exits
  # before any component work
  git clone -q "$ORIGIN" "$SB/pub"
  sed -i '' '1a\
[ -n "${MAC_SETUP_TEST_MARK:-}" ] \&\& { echo PULLED-CODE-RAN; exit 0; }
' "$SB/pub/install.sh"
  git -C "$SB/pub" -c user.name=t -c user.email=t@t commit -qam "marker" && git -C "$SB/pub" push -q origin main
  local before after out
  before="$(git -C "$A" rev-parse HEAD)"
  out="$(cd "$A" && MAC_SETUP_TEST_MARK=1 ./install.sh update 2>&1)"; local rc=$?
  after="$(git -C "$A" rev-parse HEAD)"
  assert_eq "$rc" "0" &&
  assert_contains "$out" "PULLED-CODE-RAN" &&
  [ "$before" != "$after" ] || _fail "HEAD did not advance"
}

t_update_survives_pull_failure() {
  sandbox nopull
  git -C "$A" remote set-url origin "$SB/nowhere.git"
  # with no recorded selection and no tty, resolution stops before any install
  local out; out="$(cd "$A" && ./install.sh update </dev/null 2>&1)"
  assert_contains "$out" "pull failed"
}

t_bootstrap_honours_repo_pointer() {
  sandbox boot
  mv "$A" "$SB/elsewhere"
  mkdir -p "$HOME/.config/mac-setup"; ln -sfn "$SB/elsewhere" "$HOME/.config/mac-setup/repo"
  local out; out="$("$SB/elsewhere/bootstrap.sh" doctor 2>&1)"
  assert_contains "$out" "$SB/elsewhere" &&
  [ ! -e "$HOME/Workspaces/mac-setup" ] || _fail "bootstrap cloned a second copy"
}

t_relink_removes_dangling_retired_link() {
  sandbox retired
  mklink .config/zellij "$A/config/zellij"      # component retired: target no longer exists
  "$A/install.sh" relink >/dev/null 2>&1
  [ ! -L "$HOME/.config/zellij" ] && [ ! -e "$HOME/.config/zellij" ] || _fail "dangling retired link ~/.config/zellij still present"
}

t_relink_keeps_live_retired_path_and_doctor_flags_it() {
  sandbox retired-live
  mkdir -p "$HOME/.config/zellij"; : > "$HOME/.config/zellij/config.kdl"
  "$A/install.sh" relink >/dev/null 2>&1
  [ -f "$HOME/.config/zellij/config.kdl" ] || _fail "real ~/.config/zellij was removed" || return 1
  local out; out="$("$A/install.sh" doctor 2>&1)"; local rc=$?
  assert_eq "$rc" "0" &&
  assert_contains "$out" "stale" &&
  assert_contains "$out" ".config/zellij"
}

t_ghostty_component_links_alacritty_rescue() {
  sandbox rescue
  ( cd "$A" && MAC_SETUP_LIB=1 . ./install.sh && ensure_repo_link >/dev/null && link_component ghostty >/dev/null ) || return 1
  assert_via_pointer .config/alacritty config/alacritty &&
  assert_resolves .config/alacritty "$A/config/alacritty" &&
  [ -f "$HOME/.config/alacritty/alacritty.toml" ] || _fail "alacritty.toml missing from the restored config"
}

# --- runner ---------------------------------------------------------------------
run() {
  local t="$1"
  if ( "$t" ); then green "  ok   $t"; PASS=$((PASS+1))
  else red   "  FAIL $t"; FAIL=$((FAIL+1)); FAILED="$FAILED $t"; fi
}

trap 'rm -rf "$TMPROOT"' EXIT
if [ $# -gt 0 ]; then for t in "$@"; do run "$t"; done
else for t in $(declare -F | awk '$3 ~ /^t_/ {print $3}'); do run "$t"; done; fi
echo; echo "passed $PASS, failed $FAIL${FAILED:+ ->$FAILED}"
[ "$FAIL" -eq 0 ]
