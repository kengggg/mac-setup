# Neovim cheat sheet

Leader key is `Space`. Press `Space` and wait — which-key pops up the available follow-ups.

## Find & search — Telescope

| Key | Action |
|-----|--------|
| `Space f f` | find files |
| `Space f g` | live grep across project |
| `Space f b` | open buffers |
| `Space f h` | help tags |
| `Space f d` | diagnostics list |

Inside a picker: `Ctrl j` / `Ctrl k` move, `Enter` open, `Ctrl v` open in vsplit, `Esc` close.

## Files & explorer

| Key | Action |
|-----|--------|
| `Space e` | toggle file explorer |
| `Space w` | save file |
| `Space q` | close buffer |

## Buffers & windows

| Key | Action |
|-----|--------|
| `Shift l` / `Shift h` | next / previous buffer |
| `Ctrl h` `Ctrl j` `Ctrl k` `Ctrl l` | move between splits |
| `:vsplit` / `:split` | split vertical / horizontal |

## Code — LSP

| Key | Action |
|-----|--------|
| `g d` | go to definition |
| `g D` | go to declaration |
| `K` | hover docs |
| `g r r` | references |
| `g r n` | rename symbol |
| `g r a` | code action |
| `g r i` | implementation |
| `[ d` / `] d` | previous / next diagnostic |
| `Space c a` | code action |
| `Space r n` | rename symbol |

## Completion popup — blink.cmp

| Key | Action |
|-----|--------|
| `Enter` | accept |
| `Ctrl Space` | open menu |
| `Tab` / `Shift Tab` | next / prev snippet field |
| `Ctrl e` | dismiss |

## Comment

| Key | Action |
|-----|--------|
| `g c c` | toggle comment on line |
| `g c` | toggle comment on selection, in visual mode |

## Git — gitsigns

Signs show in the gutter. Commands:

| Command | Action |
|---------|--------|
| `:Gitsigns preview_hunk` | preview change |
| `:Gitsigns stage_hunk` | stage change |
| `:Gitsigns reset_hunk` | discard change |
| `:Gitsigns blame_line` | blame current line |

## Formatting

Format runs automatically on save via conform.nvim. Manual:

```
:lua require("conform").format()
```

## Managing the setup

| Command | Action |
|---------|--------|
| `:Lazy` | plugin manager |
| `:Mason` | install / manage LSP servers + formatters |
| `:checkhealth` | diagnose problems |
| `:TSUpdate` | update treesitter parsers |

## Vim essentials

| Key | Action |
|-----|--------|
| `i` / `a` | insert before / after cursor |
| `Esc` | back to normal mode |
| `v` / `V` / `Ctrl v` | visual / line / block select |
| `:` | command mode |
| `h` `j` `k` `l` | left down up right |
| `w` `b` | next / previous word |
| `0` `$` | line start / end |
| `gg` `G` | file start / end |
| `NUMBER G` | go to line NUMBER |
| `dd` `yy` `p` | delete line / yank line / paste |
| `ciw` | change word under cursor |
| `u` / `Ctrl r` | undo / redo |
| `/text` then `n` `N` | search, next, previous |
| `:%s/old/new/g` | replace all |
| `:w` `:q` `:wq` `:q!` | save / quit / save+quit / force quit |
