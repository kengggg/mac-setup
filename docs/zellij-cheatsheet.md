# Zellij cheat sheet

The bottom bar always shows the keys for the current mode. `Ctrl g` locks/unlocks all keybindings.

## Modes

Enter a mode, then press an action key. `Esc` or `Ctrl g` returns to normal.

| Enter | Mode |
|-------|------|
| `Ctrl p` | pane |
| `Ctrl t` | tab |
| `Ctrl n` | resize |
| `Ctrl h` | move |
| `Ctrl s` | scroll / search |
| `Ctrl o` | session |
| `Ctrl q` | quit zellij |

## Quick keys — no mode needed

| Key | Action |
|-----|--------|
| `Alt n` | new pane |
| `Alt h` `Alt l` | focus pane left/right, or switch tab |
| `Alt j` `Alt k` | focus pane down/up |
| `Alt =` `Alt -` | grow / shrink pane |
| `Alt [` `Alt ]` | previous / next layout |
| `Alt f` | toggle floating panes |

## Pane mode — `Ctrl p`

| Key | Action |
|-----|--------|
| `n` | new pane |
| `d` | split down |
| `r` | split right |
| `s` | new stacked pane |
| `x` | close focused pane |
| `f` | toggle fullscreen |
| `w` | toggle floating |
| `z` | toggle pane frame |
| `c` | rename pane |
| `arrows` | focus pane |

## Tab mode — `Ctrl t`

| Key | Action |
|-----|--------|
| `n` | new tab |
| `x` | close tab |
| `r` | rename tab |
| `1`–`9` | go to tab number |
| `arrows` | previous / next tab |
| `s` | toggle sync to all panes in tab |

## Resize mode — `Ctrl n`

| Key | Action |
|-----|--------|
| `+` `=` `-` | grow / shrink |
| `h` `j` `k` `l` | grow toward direction |
| `H` `J` `K` `L` | shrink from direction |

## Scroll / search mode — `Ctrl s`

| Key | Action |
|-----|--------|
| `arrows` / `PgUp` `PgDn` | scroll |
| `s` | search |
| `e` | edit scrollback in `$EDITOR` |

## Session mode — `Ctrl o`

| Key | Action |
|-----|--------|
| `d` | detach, leaves session running |
| `w` | session manager |

In the session manager, kill/delete uses the forward-Delete key: on a Mac press `Fn` `Delete`.

## CLI

| Command | Action |
|---------|--------|
| `zellij` | start a new session |
| `zellij ls` | list sessions |
| `zellij attach NAME` | reattach |
| `zellij attach -c NAME` | attach or create NAME |
| `zellij kill-session NAME` | kill one running session |
| `zellij delete-session NAME` | remove one exited session |
| `zellij kill-all-sessions` | kill all running |
| `zellij delete-all-sessions` | remove all exited |
