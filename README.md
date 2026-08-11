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
MAC_SETUP_COMPONENTS="ghostty nvim agents" /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
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
| macOS | system tweaks (⌃⌘-drag to move any window) |

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
| `apps` | `brew bundle` of the Brewfile GUI apps |
| `macos` | system tweaks (⌃⌘-drag window moving) |

| Mode | Components |
|------|-----------|
| `full` | everything |
| `partial` | interactive checklist — any subset |

```sh
./install.sh                     # interactive menu (full / partial)
./install.sh --mode full         # everything
./install.sh --mode partial      # component checklist
./install.sh ghostty nvim        # run specific components
./install.sh update              # replay this machine's recorded selection
```

Mode runs record themselves to `~/.config/mac-setup/selection` (untracked,
per-machine). One-off component runs don't change the record. Retired
component names in old records warn and skip; a failing component doesn't
abort the run — the rest still execute, and the script ends with the list
of components to re-run.

## What the installer will NOT do

- **Run as root or sudo.** Anything needing privileges is printed as an
  instruction instead.
- **Upgrade what's already installed.** `apps` converges on missing packages
  only; upgrading is `brew upgrade`'s job, done deliberately.
- **Touch an app that already exists in `/Applications`** — however it was
  installed. Present apps are skipped by name and keep updating themselves.
- **Install from the App Store.** Sign-in can't be pre-checked and attempts
  pop auth dialogs mid-run. The Brewfile documents manual `mas install`
  one-liners (LINE, Amphetamine, Xcode) instead.

## Second machine

Both paths use the same repo, symlinks, and `update` flow — pick per machine:

```sh
# the same setup as the main machine:
MAC_SETUP_MODE=full /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"

# terminals + agents only (leaves shell, prompt, and app list alone):
MAC_SETUP_COMPONENTS="ghostty nvim agents" /bin/bash -c "$(curl -fsSL …/bootstrap.sh)"
```

Agent CLIs (`claude`, `codex`, `grok`) each prompt for their own sign-in on
first run — credentials never transfer through this repo.

## Updating other machines

Configs are symlinks — `git pull` updates them instantly. To also pick up
anything new (packages, provisioning, components added to the repo later),
replay the machine's recorded selection:

```sh
cd ~/Workspaces/mac-setup && git pull && ./install.sh update
```

`update` re-resolves a recorded `full` mode at run time, so a component newly
added to full gets installed automatically; partial runs replay their exact
component list. Machines without a record yet are prompted once, then
remembered. Everything is idempotent, so replaying is safe.

Or, if you know exactly what changed, run just that component:

| What changed | Then run |
|--------------|----------|
| configs only — ghostty, herdr, init.lua tweaks | nothing |
| nvim plugins, parsers, LSP servers, nvim deps | `./install.sh nvim` |
| Brewfile apps | `./install.sh apps` |
| shell, dotfiles, omz plugins | `./install.sh shell` |
| dev tools | `./install.sh devtools` |
| agent CLIs or statusline | `./install.sh agents` |
| macOS tweaks | `./install.sh macos` |

## Machine-specific config

The tracked `.zshrc` is portable. Per-machine tool inits (conda, nvm, language
managers, app PATHs, secrets) go in `~/.zshrc.local`, which is untracked and
sourced at the end of `.zshrc` if present.

## Migrating an already-configured machine

GUI apps that already exist are left alone (see above), so migration is mostly
about the shell. `install.sh` backs up any existing file to
`name.bak-<timestamp>` before linking, and re-runs make no new backups. After
the first run on a machine that already had a setup:

1. Open the backup, e.g. `~/.zshrc.bak-<timestamp>`.
2. Move its machine-specific bits (conda, nvm, work paths) into `~/.zshrc.local`.
3. `source ~/.zshrc` or open a new shell.

## Troubleshooting

| Symptom | Cause → fix |
|---------|-------------|
| `Error: /opt/homebrew is not writable` | Homebrew belongs to another user account (machine first set up under a different login). Fix once from an admin account: `sudo chown -R <you> /opt/homebrew`, then re-run. The installer checks this up front and stops early with this instruction. |
| oh-my-zsh warns "insecure completion-dependent directories" on every new shell | Completion files owned by another account. `./install.sh shell` auto-fixes what it can by replacing the symlinks with owned copies. (`sudo chown` does NOT work here — macOS App Management blocks writes into other apps' bundles, even for root.) |
| Powerlevel10k "console output during zsh initialization" warning | Collateral of anything printing during startup (like the warning above); fix the underlying message and this disappears. |
| A cask upgrade fails, e.g. font "source … is not there" | Files were deleted outside brew. `brew uninstall --cask --force <name> && brew install --cask <name>`. Setup runs never upgrade, so this only bites manual `brew upgrade`. |
| App Store apps missing after a run | By design — install manually while signed in; one-liners are at the bottom of the `Brewfile`. |
| ⌃⌘-drag window moving doesn't work | The pref applies to apps launched after `./install.sh macos` ran — fully quit (⌘Q) and reopen the app. |

## Notes

- Apple Silicon only; assumes Homebrew at `/opt/homebrew`
- `~/.zprofile` is untracked; `install.sh` writes the brew `shellenv` line
- Symlinks point into this repo; don't move it without re-running the affected components
- The lanna-tone theme's source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme). The ghostty copy here is synced with `./scripts/sync-theme.sh` — edit the theme repo, not the copy.
- Ghostty renders Thai (U+0E00–U+0E7F) in Arundina Sans Mono via `font-codepoint-map`.
- Ghostty auto-launches **herdr** (agent multiplexer, `ctrl+b` prefix). herdr's config is linked file-level (`~/.config/herdr` also holds runtime state); its in-app settings (`ctrl+b s`) write through the symlink, so TUI changes show up as git diffs here.
- Ghostty + herdr follow macOS appearance with stock themes (TokyoNight Day / TokyoNight); lanna-tone lives on as Ghostty's revert copy in `config/ghostty/themes/`.

## Layout

```
mac-setup/
├── Brewfile                     # dependencies + apps
├── bootstrap.sh                 # zero-to-setup entry point
├── install.sh                   # idempotent installer
├── scripts/nvim-provision.lua   # headless treesitter + Mason
├── scripts/sync-theme.sh        # pull lanna-tone from its canonical repo
├── claude/                      # statusline script -> ~/.claude
├── config/                      # -> ~/.config/{ghostty,herdr,nvim}
└── home/                        # -> ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```
