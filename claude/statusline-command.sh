#!/bin/bash
# Claude Code status line: directory, git branch/status, model name,
# active account badge (Team/Personal), 5-hour session usage bar,
# context window usage bar, and a short session id.
#
# Adapted from https://gist.github.com/alphygogo/631709e28d3078abb8fe77a2404b4225

input=$(cat)

dir=$(echo "$input" | jq -r '.workspace.current_dir')
model=$(echo "$input" | jq -r '.model.display_name')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
session_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Read the active account/profile from the app config (not the stdin payload)
# so an account switch via `/login` is reflected on the very next render.
# CLAUDE_STATUSLINE_CONFIG overrides the config path for testing.
claude_config="${CLAUDE_STATUSLINE_CONFIG:-$HOME/.claude.json}"
account_email=$(jq -r '.oauthAccount.emailAddress // empty' "$claude_config" 2>/dev/null)
org_type=$(jq -r '.oauthAccount.organizationType // empty' "$claude_config" 2>/dev/null)
org_name=$(jq -r '.oauthAccount.organizationName // empty' "$claude_config" 2>/dev/null)

# Shorten $HOME to ~ like a typical shell prompt.
display_dir="${dir/#$HOME/~}"

git_segment=""
if git -C "$dir" --no-optional-locks rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$dir" --no-optional-locks branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(git -C "$dir" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  fi
  if [ -n "$branch" ]; then
    if [ -n "$(git -C "$dir" --no-optional-locks status --porcelain 2>/dev/null)" ]; then
      # Dirty working tree -> yellow with a marker.
      git_segment=$(printf '\033[33m⎇\033[0m %s \033[33m*\033[0m' "$branch")
    else
      # Clean working tree -> green.
      git_segment=$(printf '\033[32m⎇\033[0m %s\033[0m' "$branch")
    fi
  fi
fi

# Build a labeled progress bar, e.g. "5h [██████░░░░] 60%". Colored green
# (<50%), yellow (50-79%), or red (>=80%) based on how full it is.
make_bar() {
  label="$1"
  pct="$2"
  [ -z "$pct" ] && return
  pct_int=$(printf '%.0f' "$pct")
  width=10
  filled=$(( pct_int * width / 100 ))
  [ "$filled" -gt "$width" ] && filled=$width
  [ "$filled" -lt 0 ] && filled=0
  empty=$(( width - filled ))

  if [ "$pct_int" -ge 80 ]; then
    bar_color='\033[31m'   # red
  elif [ "$pct_int" -ge 50 ]; then
    bar_color='\033[33m'   # yellow
  else
    bar_color='\033[32m'   # green
  fi

  bar_filled=$(printf '%*s' "$filled" '' | tr ' ' '█')
  bar_empty=$(printf '%*s' "$empty" '' | tr ' ' '░')

  printf '\033[2m%s\033[0m %b[%s%s]\033[0m %s%%' "$label" "$bar_color" "$bar_filled" "$bar_empty" "$pct_int"
}

session_segment=$(make_bar "5h" "$session_pct")
context_segment=$(make_bar "ctx" "$used_pct")

# Account badge keyed off the profile's organizationType so Team vs Personal
# profiles on the SAME email are distinguished: Team (cyan) shows the org
# name, Personal (magenta) shows the email local part, "no-acct" (dim) when
# logged out / field missing.
if [ -n "$account_email" ]; then
  account_local="${account_email%%@*}"
  case "$org_type" in
    claude_team|claude_enterprise)
      account_segment=$(printf '\033[36mTeam:%s\033[0m' "${org_name:-$account_local}")
      ;;
    *)
      account_segment=$(printf '\033[35mPersonal:%s\033[0m' "$account_local")
      ;;
  esac
else
  account_segment=$(printf '\033[2mno-acct\033[0m')
fi

# Short session id so it's obvious when two tabs share (or don't share) a
# session.
sid_segment=""
if [ -n "$session_id" ]; then
  sid_segment=$(printf '\033[2m#%s\033[0m' "${session_id:0:8}")
fi

out=$(printf '\033[34m📁 %s\033[0m' "$display_dir")
if [ -n "$git_segment" ]; then
  out="$out  $git_segment"
fi
out="$out  \033[2m%s\033[0m"
args=("$model")

out="$out  %s"
args+=("$account_segment")

if [ -n "$session_segment" ]; then
  out="$out  %s"
  args+=("$session_segment")
fi
if [ -n "$context_segment" ]; then
  out="$out  %s"
  args+=("$context_segment")
fi
if [ -n "$sid_segment" ]; then
  out="$out  %s"
  args+=("$sid_segment")
fi

printf "$out\n" "${args[@]}"
