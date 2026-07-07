# mac-setup

Machine setup & resurrection for Apple Silicon Macs.

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

Installs Command Line Tools, clones to `~/Workspaces/mac-setup`, runs `install.sh`, which prompts for a mode. To pick non-interactively:

```sh
MAC_SETUP_MODE=full    /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"   # everything
MAC_SETUP_MODE=minimal /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"   # alacritty+zellij+nvim only
```

## Sets up

| Layer | Contents |
|-------|----------|
| Brew | `zellij` `neovim` `fzf` `fd` `ripgrep` `eza` `gh` `node`, MesloLGS Nerd Font, Alacritty, Ghostty, + apps in `Brewfile` |
| Fonts | MesloLGS Nerd Font (Latin/code), Arundina Sans Mono (Thai, from [tlwg/fonts-arundina](https://github.com/tlwg/fonts-arundina)) |
| Shell | oh-my-zsh, Powerlevel10k, `zsh-autosuggestions`, `zsh-syntax-highlighting` |
| Dev tools | Miniforge (conda + mamba), nvm + Node LTS, Grok CLI — init written to `~/.zshrc.local` |
| Configs | Alacritty, Ghostty, Zellij, Neovim, `.zshrc`, `.p10k.zsh`, `.vimrc` |

Configs are symlinked from this repo; commit + push to sync across machines.

## Cheat sheets

- [Zellij](docs/zellij-cheatsheet.md)
- [Neovim](docs/nvim-cheatsheet.md)

## Modes & components

`install.sh` runs **components**; modes are presets of them. Everything is
idempotent and backs up existing files to `name.bak-<timestamp>`.

| Component | Installs + links |
|-----------|------------------|
| `alacritty` | alacritty + MesloLGS font → `~/.config/alacritty` |
| `ghostty` | ghostty + MesloLGS + Arundina Sans Mono (Thai) → `~/.config/ghostty`, ⇧⌘M Zoom binding |
| `zellij` | zellij → `~/.config/zellij` |
| `nvim` | neovim, ripgrep, fd, fzf, tree-sitter-cli, node → `~/.config/nvim` + provision |
| `shell` | oh-my-zsh, p10k, zsh plugins, eza → `.zshrc`, `.p10k.zsh`, `.vimrc` |
| `devtools` | Miniforge, nvm+Node, Grok → init in `~/.zshrc.local` |
| `claude` | Claude Code statusline: symlink script + merge `statusLine` into `~/.claude/settings.json` (jq) |

| Mode | Components |
|------|-----------|
| `full` | everything (+ `apps`, `macos`) |
| `minimal` | alacritty, ghostty, zellij, nvim — **leaves your shell untouched** |
| `select` | interactive checklist |

```sh
./install.sh                     # interactive menu
./install.sh --mode full         # or minimal / select
./install.sh alacritty nvim      # run specific components
./install.sh update              # replay this machine's recorded selection
```

Mode runs record themselves to `~/.config/mac-setup/selection` (untracked,
per-machine). One-off component runs don't change the record.

## Adding things

- App: add `cask "name"` to `Brewfile`, run `./install.sh apps`
- Dotfile: add to `config/` or `home/`, add a `link` line in the relevant `comp_*` function, re-run that component
- macOS tweak: edit `comp_macos` in `install.sh`

## Layout

```
mac-setup/
├── Brewfile                     # dependencies + apps
├── bootstrap.sh                 # zero-to-setup entry point
├── install.sh                   # idempotent installer
├── scripts/nvim-provision.lua   # headless treesitter + Mason
├── config/                      # -> ~/.config/{alacritty,ghostty,zellij,nvim}
└── home/                        # -> ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```

## Updating other machines

Configs are symlinks — `git pull` updates them instantly. To also pick up
anything new (packages, provisioning, components added to the repo later —
e.g. Ghostty), replay the machine's recorded selection:

```sh
cd ~/Workspaces/mac-setup && git pull && ./install.sh update
```

`update` re-resolves the recorded mode at run time, so a component newly
added to that mode gets installed automatically. Machines set up before the
record existed are prompted once, then remembered. Everything is idempotent,
so replaying is safe.

Or, if you know exactly what changed, run just that component:

| What changed | Then run |
|--------------|----------|
| configs only — alacritty, ghostty, zellij, init.lua tweaks | nothing |
| a new terminal/program component (e.g. ghostty) | `./install.sh ghostty` |
| nvim plugins, parsers, LSP servers, nvim deps | `./install.sh nvim` |
| Brewfile apps | `./install.sh apps` |
| shell, dotfiles, omz plugins | `./install.sh shell` |
| dev tools | `./install.sh devtools` |
| Claude Code statusline | `./install.sh claude` |

## Machine-specific config

The tracked `.zshrc` is portable. Per-machine tool inits (conda, nvm, language
managers, app PATHs, secrets) go in `~/.zshrc.local`, which is untracked and
sourced at the end of `.zshrc` if present.

## Migrating an already-configured machine

`install.sh symlinks` backs up any existing file to `name.bak-<timestamp>`
before linking, and is idempotent (re-runs make no new backups). After the
first run on a machine that already had a setup:

1. Open the backup, e.g. `~/.zshrc.bak-<timestamp>`.
2. Move its machine-specific bits (conda, nvm, work paths) into `~/.zshrc.local`.
3. `source ~/.zshrc` or open a new shell.

## Notes

- Apple Silicon only; assumes Homebrew at `/opt/homebrew`
- `~/.zprofile` is untracked; `install.sh` writes the brew `shellenv` line
- Symlinks point into this repo; don't move it without rerunning `./install.sh symlinks`
- The lanna-tone theme's source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme). The alacritty + ghostty + zellij copies here are synced with `./scripts/sync-theme.sh` — edit the theme repo, not these copies.
- Ghostty renders Thai (U+0E00–U+0E7F) in Arundina Sans Mono via `font-codepoint-map`; Alacritty can't do per-script fonts, so both terminals stay installed side by side.
