# mac-setup

Machine setup & resurrection for Apple Silicon Macs.

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

Installs Command Line Tools, clones to `~/Workspaces/mac-setup`, runs `install.sh`.

## Sets up

| Layer | Contents |
|-------|----------|
| Brew | `zellij` `neovim` `fzf` `fd` `ripgrep` `eza` `gh` `node`, MesloLGS Nerd Font, Alacritty, + apps in `Brewfile` |
| Shell | oh-my-zsh, Powerlevel10k, `zsh-autosuggestions`, `zsh-syntax-highlighting` |
| Dev tools | Miniforge (conda + mamba), nvm + Node LTS, Grok CLI — init written to `~/.zshrc.local` |
| Configs | Alacritty, Zellij, Neovim, `.zshrc`, `.p10k.zsh`, `.vimrc` |

Configs are symlinked from this repo; commit + push to sync across machines.

## Cheat sheets

- [Zellij](docs/zellij-cheatsheet.md)
- [Neovim](docs/nvim-cheatsheet.md)

## Steps

Order: `homebrew → brew → zsh → tools → symlinks → nvim → macos`. Idempotent; existing files backed up to `name.bak-<timestamp>`.

```sh
./install.sh             # all steps
./install.sh symlinks    # relink dotfiles
./install.sh brew        # install/update Brewfile
./install.sh tools       # install miniforge / nvm / grok
./install.sh nvim        # provision plugins/servers
```

## Adding things

- App: add `cask "name"` to `Brewfile`, run `./install.sh brew`
- Dotfile: add to `config/` or `home/`, add a `link` line in `step_symlinks`, run `./install.sh symlinks`
- macOS tweak: edit `step_macos` in `install.sh`

## Layout

```
mac-setup/
├── Brewfile                     # dependencies + apps
├── bootstrap.sh                 # zero-to-setup entry point
├── install.sh                   # idempotent installer
├── scripts/nvim-provision.lua   # headless treesitter + Mason
├── config/                      # -> ~/.config/{alacritty,zellij,nvim}
└── home/                        # -> ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```

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
