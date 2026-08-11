# herdr cheat sheet

One prefix, no modes: press `Ctrl b`, release, then an action key.
`Ctrl b ?` shows every active binding. herdr is mouse-native too — click
spaces/tabs in the sidebar, right-click for menus, drag-select to copy.

**Model:** session → **spaces** (workspaces, one per repo/task) → tabs → panes.
Everything keeps running when you detach or close the window.

## Session

| Key | Action |
|-----|--------|
| `Ctrl b` `q` | detach (server + agents keep running) |
| `herdr` | launch / reattach (shell) |
| `Ctrl b` `s` | settings TUI (theme, toasts, integrations) |
| `Ctrl b` `Shift r` | reload config.toml |
| `Ctrl b` `?` | show all keybindings |

## Spaces (workspaces)

| Key | Action |
|-----|--------|
| `Ctrl b` `Shift n` | new space |
| `Ctrl b` `w` | space picker |
| `Ctrl b` `g` | goto picker (fuzzy jump anywhere) |
| `Ctrl b` `Shift w` | rename space |
| `Ctrl b` `Shift d` | close space (asks to confirm) |
| `Ctrl b` `b` | toggle sidebar |
| `Ctrl b` `Shift g` | new git worktree space |

## Tabs

| Key | Action |
|-----|--------|
| `Ctrl b` `c` | new tab (prompts for name) |
| `Ctrl b` `n` / `p` | next / previous tab |
| `Ctrl b` `1..9` | jump to tab |
| `Ctrl b` `Shift t` | rename tab |
| `Ctrl b` `Shift x` | close tab |

## Panes

| Key | Action |
|-----|--------|
| `Ctrl b` `v` | split right |
| `Ctrl b` `-` | split down |
| `Ctrl b` `h/j/k/l` | focus left/down/up/right |
| `Ctrl b` `Shift h/j/k/l` | swap pane in direction |
| `Ctrl b` `Tab` / `Shift Tab` | cycle panes |
| `Ctrl b` `z` | zoom (fullscreen toggle) |
| `Ctrl b` `r` | resize mode |
| `Ctrl b` `Shift p` | rename pane |
| `Ctrl b` `x` | close pane |

## Scrollback & copy

| Key | Action |
|-----|--------|
| `Ctrl b` `[` | copy mode |
| — `h/j/k/l` `w/b/e` `{` `}` | vim motions |
| — `Ctrl u` / `Ctrl d`, `PgUp/PgDn` | page around |
| — `v` or `Space` | start selection |
| — `y` or `Enter` | copy + exit |
| — `q` or `Esc` | leave copy mode |
| `Ctrl b` `e` | open scrollback in $EDITOR |
| mouse drag | select + copy, no mode needed |

## Agents

The sidebar shows every agent's state across all spaces:
**blocked** (needs you) · **working** · **done** (finished, unseen) · **idle**.
Claude Code is auto-detected — no setup needed.

| Key | Action |
|-----|--------|
| `Ctrl b` `o` | jump to what the last notification was about |

Useful from any shell: `herdr agent list`, `herdr agent wait <n> --status idle`,
`herdr worktree create --branch <name>`.

## Optional: direct chords (no prefix)

Direct chords aren't on by default; add to `config/herdr/config.toml` `[keys]`:

```toml
focus_pane_left  = "ctrl+alt+h"   # plus j/k/l
new_tab          = "ctrl+alt+c"
zoom             = "ctrl+alt+z"
```
