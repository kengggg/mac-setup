# mac-setup

Personal machine **setup & resurrection** tool for Apple Silicon Macs.
One command brings a fresh Mac to my known-good state: Homebrew, CLI tools,
fonts, GUI apps, oh-my-zsh + Powerlevel10k, and my terminal stack
(Alacritty + Zellij + Neovim).

## What it sets up

| Layer | Contents |
|-------|----------|
| **Brew** | `zellij`, `neovim`, `fzf`, `fd`, `ripgrep`, `eza`, `git`, `gh`, `node`, MesloLGS Nerd Font, Alacritty — plus any GUI apps in the `Brewfile` |
| **Shell** | oh-my-zsh + Powerlevel10k + `zsh-autosuggestions` + `zsh-syntax-highlighting` |
| **Configs** | Alacritty, Zellij, Neovim (full IDE config, plugin versions pinned via `lazy-lock.json`), `.zshrc`, `.p10k.zsh`, `.vimrc` |

Config files are **symlinked** from this repo into place, so edits on any
machine — once committed and pushed — sync everywhere.

## One-liner (works only while this repo is **public**)

No GitHub auth, no prior checkout — Homebrew-style:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

`bootstrap.sh` installs Command Line Tools if needed, clones this repo to
`~/Workspaces/mac-setup`, and runs `install.sh`. (A private repo can't be
fetched this way without a token — use the `gh` flow below instead.)

## Quick start (private repo, machine with `gh` set up)

```sh
gh repo clone kengggg/mac-setup ~/Workspaces/mac-setup
~/Workspaces/mac-setup/install.sh
```

## Fresh Mac, from zero

A brand-new Mac has no `git`, no Homebrew, and isn't logged into GitHub. Run
these in order, then the quick-start above:

```sh
# 1. Command Line Tools (provides git) — accept the GUI prompt
xcode-select --install

# 2. Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
eval "$(/opt/homebrew/bin/brew shellenv)"

# 3. GitHub auth (this repo is private)
brew install gh && gh auth login

# 4. clone + run
gh repo clone kengggg/mac-setup ~/Workspaces/mac-setup
~/Workspaces/mac-setup/install.sh
```

`install.sh` is **idempotent** — safe to re-run anytime; it skips what's already
done and backs up any existing config file (to `name.bak-<timestamp>`) before
linking.

## Running individual steps

```sh
./install.sh symlinks      # just (re)link the dotfiles
./install.sh brew          # just install/update Brewfile packages
./install.sh nvim          # just provision Neovim plugins/servers
```

Steps, in order: `homebrew → brew → zsh → symlinks → nvim → macos`.

## Adding things

- **A new app**: add a line to `Brewfile`, e.g. `cask "slack"`, then
  `./install.sh brew`. Find names with `brew search --cask <name>`.
- **A new dotfile**: drop it under `config/` or `home/`, add a `link …` line to
  `step_symlinks` in `install.sh`, and re-run `./install.sh symlinks`.
- **macOS system tweaks**: edit `step_macos` in `install.sh`.

## Layout

```
mac-setup/
├── Brewfile                 # declarative dependencies + apps
├── install.sh               # idempotent installer (orchestrates the steps)
├── scripts/nvim-provision.lua   # headless treesitter + Mason install
├── config/                  # → ~/.config/{alacritty,zellij,nvim}
└── home/                    # → ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```

## Notes

- **Apple Silicon only** (assumes Homebrew at `/opt/homebrew`).
- `~/.zprofile` is **not** tracked — `install.sh` writes the Homebrew `shellenv`
  line into it, because its path is machine/architecture-specific.
- The repo lives at `~/Workspaces/mac-setup`; symlinks point into it, so don't
  move it without re-running `./install.sh symlinks`.
