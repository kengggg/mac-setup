# mac-setup

Machine setup & resurrection for Apple Silicon Macs.

## Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

Installs Command Line Tools, clones to `~/Workspaces/mac-setup`, runs `install.sh`, which prompts for a mode. To pick non-interactively:

```sh
MAC_SETUP_MODE=full /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"   # everything

# exact components, recorded for later `update`:
MAC_SETUP_COMPONENTS="ghostty nvim agents"           /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
MAC_SETUP_COMPONENTS="ghostty nvim"                  /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"   # terminal + editor only
```

## Sets up

| Layer | Contents |
|-------|----------|
| Brew | `herdr` `neovim` `fzf` `fd` `ripgrep` `eza` `gh` `node`, MesloLGS Nerd Font, Ghostty, + apps in `Brewfile` |
| Fonts | MesloLGS Nerd Font (Latin/code), Arundina Sans Mono (Thai, from [tlwg/fonts-arundina](https://github.com/tlwg/fonts-arundina)) |
| Shell | oh-my-zsh, Powerlevel10k, `zsh-autosuggestions`, `zsh-syntax-highlighting` |
| Dev tools | Miniforge (conda + mamba), nvm + Node LTS — init written to `~/.zshrc.local` |
| Agent CLIs | Claude Code (+ statusline), Codex, Grok |
| Configs | Ghostty, herdr, Neovim, `.zshrc`, `.p10k.zsh`, `.vimrc` |

Configs are symlinked from this repo; commit + push to sync across machines.

## Cheat sheets

- [herdr](docs/herdr-cheatsheet.md)
- [Neovim](docs/nvim-cheatsheet.md)

## Modes & components

`install.sh` runs **components**; each component is already a group of
programs (`agents` = Claude Code + Codex + Grok, `apps` = the whole
Brewfile). Everything is idempotent and backs up existing files to
`name.bak-<timestamp>`.

| Component | Installs + links |
|-----------|------------------|
| `ghostty` | ghostty + herdr + MesloLGS + Arundina Sans Mono (Thai) → `~/.config/ghostty` + `~/.config/herdr/config.toml`, ⇧⌘M Zoom binding |
| `nvim` | neovim, ripgrep, fd, fzf, tree-sitter-cli, node → `~/.config/nvim` + provision |
| `shell` | oh-my-zsh, p10k, zsh plugins, eza → `.zshrc`, `.p10k.zsh`, `.vimrc` |
| `devtools` | Miniforge, nvm+Node → init in `~/.zshrc.local` |
| `agents` | Claude Code (native installer) + statusline (`statusLine` jq-merged into `~/.claude/settings.json`), Codex CLI (brew), Grok CLI → init in `~/.zshrc.local` |

| Mode | Components |
|------|-----------|
| `full` | everything |
| `partial` | interactive checklist — any subset, incl. `apps`/`macos` |

```sh
./install.sh                     # interactive menu (full / partial)
./install.sh --mode full         # everything
./install.sh --mode partial      # component checklist
./install.sh ghostty nvim        # run specific components
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
├── config/                      # -> ~/.config/{ghostty,herdr,nvim}
└── home/                        # -> ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```

## Updating other machines

Configs are symlinks — `git pull` updates them instantly. To also pick up
anything new (packages, provisioning, components added to the repo later —
e.g. Ghostty), replay the machine's recorded selection:

```sh
cd ~/Workspaces/mac-setup && git pull && ./install.sh update
```

`update` re-resolves a recorded `full` mode at run time, so a component newly
added to full gets installed automatically; partial runs replay their exact
component list. Machines set up before the record existed — or with a record
from the retired `minimal`/`select` modes — are prompted once, then remembered. Everything is idempotent,
so replaying is safe.

Or, if you know exactly what changed, run just that component:

| What changed | Then run |
|--------------|----------|
| configs only — ghostty, herdr, init.lua tweaks | nothing |
| a new terminal/program component (e.g. ghostty) | `./install.sh ghostty` |
| nvim plugins, parsers, LSP servers, nvim deps | `./install.sh nvim` |
| Brewfile apps | `./install.sh apps` |
| shell, dotfiles, omz plugins | `./install.sh shell` |
| dev tools | `./install.sh devtools` |
| agent CLIs or statusline | `./install.sh agents` |

## Second machine, partial setup

To set up a machine with just Ghostty + herdr (with these configs), Neovim,
and the agent CLIs (Claude Code, Codex, Grok) — without touching its shell,
prompt, or installing the GUI app list:

```sh
MAC_SETUP_COMPONENTS="ghostty nvim agents" /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

The selection is recorded, so keeping the machine current later is the same
as any other machine: `cd ~/Workspaces/mac-setup && git pull && ./install.sh update`.
Config-only changes arrive with plain `git pull` (symlinks).

Note: the agent CLIs need their own sign-ins on that machine (`claude`,
`codex`, `grok` each prompt on first run) — accounts and credentials don't
transfer through this repo.

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
- App Store apps in the `Brewfile` (LINE, Amphetamine, Xcode) install via `mas`, which needs you signed into the App Store first
- `~/.zprofile` is untracked; `install.sh` writes the brew `shellenv` line
- Symlinks point into this repo; don't move it without rerunning `./install.sh symlinks`
- The lanna-tone theme's source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme). The ghostty copy here is synced with `./scripts/sync-theme.sh` — edit the theme repo, not the copy.
- Ghostty renders Thai (U+0E00–U+0E7F) in Arundina Sans Mono via `font-codepoint-map`.
- Multiplexer: Ghostty auto-launches **herdr** (agent multiplexer, `ctrl+b` prefix) — winner of the 2026-07 trial vs zellij (zellij and Alacritty both removed 2026-08; Ghostty is the only terminal). herdr's config is linked file-level (`~/.config/herdr` also holds runtime state); its in-app settings (`ctrl+b s`) write through the symlink, so TUI changes show up as git diffs here.
- Ghostty + herdr follow macOS appearance with stock themes (TokyoNight Day / TokyoNight) — lanna-tone didn't sit well with herdr's UI; it lives on as Ghostty's revert copy, synced in `config/ghostty/themes/`.
