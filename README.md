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
| Brew | `herdr` `neovim` `fzf` `fd` `ripgrep` `eza` `gh` `node`, MesloLGS Nerd Font, Ghostty, Alacritty, + apps in `Brewfile` |
| Fonts | MesloLGS Nerd Font (Latin/code), Arundina Sans Mono (Thai, from [tlwg/fonts-arundina](https://github.com/tlwg/fonts-arundina)) |
| Shell | oh-my-zsh, Powerlevel10k, `zsh-autosuggestions`, `zsh-syntax-highlighting` |
| Dev tools | Miniforge (conda + mamba), nvm + Node LTS — init written to `~/.zshrc.local` |
| Agent CLIs | Claude Code (+ statusline), Codex, Grok |
| Terminals | **Ghostty** opens plain login zsh; launch **herdr** sessions manually when wanted. **Alacritty** is the rescue terminal — plain login zsh, its own config, so there is always a way in when Ghostty or herdr misbehave |
| Configs | Ghostty, herdr, Alacritty, Neovim, `.zshrc`, `.p10k.zsh`, `.vimrc` |
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
| `ghostty` | ghostty + herdr + MesloLGS + Arundina Sans Mono (Thai) → `~/.config/ghostty` + `~/.config/herdr/config.toml`, ⇧⌘M Zoom binding; plus alacritty (rescue terminal) → `~/.config/alacritty` |
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
./install.sh update              # git pull, then replay this machine's recorded selection
./install.sh doctor              # read-only: are all managed links healthy? (+ git state)
./install.sh relink              # repair links after moving the clone — no installs
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
~/.config/mac-setup/repo/install.sh update     # pulls first, then replays
```

`update` re-resolves a recorded `full` mode at run time, so a component newly
added to full gets installed automatically; partial runs replay their exact
component list. Machines without a record yet are prompted once, then
remembered. Everything is idempotent, so replaying is safe.

### Ghostty and herdr: independent windows

Previously, every Ghostty window automatically attached to herdr's shared
`default` session, so multiple windows could show the same contents. Ghostty
now opens a plain login zsh in each window. Start herdr only when wanted,
using a different session name for each independent set of workspaces:

```sh
herdr --session work       # first window: start or reattach work
herdr --session personal   # second window: separate workspaces, tabs, panes
herdr session list         # list sessions on this Mac
herdr                     # reattach your previous default session
```

The same name always selects the same session. Named sessions share the
herdr configuration, but their workspaces, panes, and running processes are
separate. Sessions stay on the Mac where they were started; Git syncs the
configuration, not live sessions. Press `Ctrl+B`, release, then `Q` to detach
back to zsh while the session keeps running. See the
[herdr cheat sheet](docs/herdr-cheatsheet.md) for session management commands.

To adopt this change on an existing Mac:

```sh
cd ~/.config/mac-setup/repo
git switch main
./install.sh update
```

`update` pulls the current branch, so switch to `main` first to receive merged
changes. In Ghostty, press `Cmd+Shift+,` to reload the config, then `Cmd+N` to
open a new plain-zsh window. Existing herdr panes and agents keep running;
the update does not move them into named sessions. Run `herdr` in a new
window to return to the old default session. Detaching from an older window
that auto-launched herdr may close that window rather than return to zsh.

Ghostty now uses fixed Lanna Tone colors, with no day/night switching. In an
existing herdr client, press `Ctrl+B`, release, then `Shift+R` to reload its
config and use the terminal palette with automatic theme switching disabled.

### How links survive moves and upgrades

Every machine has one pointer, `~/.config/mac-setup/repo → <clone>`, and every
managed dotfile links *through* it (`~/.zshrc → ~/.config/mac-setup/repo/home/zshrc`).
Every installer run, whatever was selected, first converges that scheme:
re-points the pointer at the clone it runs from, adopts any managed link that
is already ours (old direct links, links left dangling by a move), adds a
one-line guard to `~/.zprofile` that speaks up if `~/.zshrc` ever dangles,
and ends with `doctor`. Real files and other people's symlinks are never
touched by that pass — creating a link stays gated by component selection.

So a machine set up before the pointer existed needs nothing special: its next
`./install.sh update` migrates it. And if you move the clone:

```sh
mv ~/Workspaces/mac-setup ~/Work/mac-setup && ~/Work/mac-setup/install.sh relink
```

`bootstrap.sh` honours the pointer too, so re-running the one-liner updates
the clone wherever it lives instead of creating a second one. And if the
pointer is dangling — the clone was moved without `relink`, or deleted —
bootstrap stops and says what to do rather than cloning a stray second copy
into the default path.

Or, if you know exactly what changed, run just that component:

| What changed | Then run |
|--------------|----------|
| configs only — ghostty, herdr, alacritty, init.lua tweaks | no installer needed after pulling; reload the affected app's config or reopen it |
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
| New terminals open with a bare `%` prompt, or print `mac-setup: ~/.zshrc is a broken link` | The clone moved (or was deleted) and the links dangle. From the clone's new location: `./install.sh relink`. `./install.sh doctor` shows exactly which links are affected. |
| Ghostty opens a plain shell instead of herdr | By design. Run `herdr --session work` to start or reattach a named session. |
| Multiple Ghostty windows show the same herdr contents | They attached to the same session. Use different names, e.g. `herdr --session work` and `herdr --session personal`, for independent workspaces and panes. |
| Ghostty won't open, or herdr is wedged | Open **Alacritty** — the rescue terminal: plain login zsh, no multiplexer, its own config, so it keeps working while you fix Ghostty/herdr (`./install.sh doctor` is a good first command there). |
| `skipping alacritty: its cask is disabled in Homebrew` (and the ghostty component warns it can't install it) | Homebrew disabled the cask (2026-09: the release fails Gatekeeper), so brew can't install it on a machine that doesn't have it yet. Setup continues without the rescue terminal; install it manually from [Alacritty's releases](https://github.com/alacritty/alacritty/releases) — its config link is already in place. |
| `doctor` says `stale ~/.config/zellij` | Leftover from the retired zellij component that is a real directory or a live link, so the installer won't touch it. Remove it yourself (and `brew uninstall zellij` if you still have the formula); dangling leftovers are removed by `relink` automatically. |

## Notes

- Apple Silicon only; assumes Homebrew at `/opt/homebrew`
- `~/.zprofile` is untracked; `install.sh` writes the brew `shellenv` line and the broken-`.zshrc` guard there
- Symlinks go through `~/.config/mac-setup/repo`; moving the clone needs one `./install.sh relink` from its new home
- `tests/link-layer.sh` exercises the link layer (pointer, adoption, moves, `doctor`, `update`'s pull, bootstrap) against a throwaway `$HOME` and a local bare remote — no brew, no network, nothing on the real machine
- The lanna-tone theme's source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme). The ghostty and alacritty copies here are synced with `./scripts/sync-theme.sh` — edit the theme repo, not the copies.
- Ghostty renders Thai (U+0E00–U+0E7F) in Arundina Sans Mono via `font-codepoint-map`. Alacritty can't do per-script fonts, which is one reason it's the rescue terminal and not the daily one.
- Alacritty stays deliberately plain: login zsh, no auto-launched program, lanna-tone theme, the same ⇧⏎ / F11 / ⇧⌘M bindings as Ghostty. Don't wire herdr (or anything else) into it.
- Ghostty opens a plain login zsh in each window. Launch **herdr** manually with `herdr --session <name>`; `herdr session list` lists saved sessions, and `ctrl+b q` detaches back to the shell while panes keep running. Bare `herdr` uses the shared default session. herdr's config is linked file-level (`~/.config/herdr` also holds runtime state); its in-app settings (`ctrl+b s`) write through the symlink, so TUI changes show up as git diffs here.
- Ghostty uses the fixed Lanna Tone theme, independent of macOS appearance. herdr uses the host terminal's palette (`name = "terminal"`, `auto_switch = false`); Alacritty also uses Lanna Tone. There is no automatic day/night theme switching.

## Layout

```
mac-setup/
├── Brewfile                     # dependencies + apps
├── bootstrap.sh                 # zero-to-setup entry point
├── install.sh                   # idempotent installer
├── scripts/nvim-provision.lua   # headless treesitter + Mason
├── scripts/sync-theme.sh        # pull lanna-tone from its canonical repo
├── tests/link-layer.sh          # link-layer tests in a throwaway $HOME
├── claude/                      # statusline script -> ~/.claude
├── config/                      # -> ~/.config/{ghostty,herdr,alacritty,nvim}
└── home/                        # -> ~/.zshrc, ~/.p10k.zsh, ~/.vimrc
```
