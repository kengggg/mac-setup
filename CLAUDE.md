# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Machine setup & resurrection for Apple Silicon Macs — a component-based installer plus the dotfiles it symlinks into place. There is no build, lint, or test suite; "development" means editing configs/installer and re-running the relevant component.

**Objective:** make a fresh machine — Keng's own or a second machine for someone else — reproduce this setup with one command, then stay in sync via git. Every machine uses the same model: clone + symlink + `git pull`.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

The repo is public, so this works with no GitHub auth. Modes are `full` (everything) and `partial` (interactive component checklist) — nothing else. `MAC_SETUP_MODE=full` makes it non-interactive; `MAC_SETUP_COMPONENTS="ghostty nvim agents"` runs an exact component list instead (the second-machine recipe — recorded like a partial run so `update` replays it).

## Commands

```sh
./install.sh                     # interactive mode menu (full / partial)
./install.sh --mode full         # everything
./install.sh --mode partial      # component checklist
./install.sh ghostty agents      # run specific components (doesn't change the machine's record)
./install.sh update              # after git pull: replay this machine's recorded selection
./scripts/sync-theme.sh          # pull lanna-tone theme copies from the canonical theme repo
```

Components: `ghostty` `nvim` `shell` `devtools` `agents` `apps` `macos` (`claude` is a deprecated alias for `agents`; `alacritty` and `zellij` were removed 2026-08 and warn-then-skip for old machine records). `agents` = Claude Code (native installer → `~/.local/bin`) + statusline, Codex CLI (brew cask), Grok CLI — deliberately separate from `devtools` (conda+nvm) so a second machine can take one without the other. Runs are recorded to `~/.config/mac-setup/selection` (untracked, per-machine): full by mode name (re-resolved at `update` time, so components later added to full get picked up), partial by exact component list. Records from the retired `minimal`/`select` modes re-prompt once (clean break, chosen deliberately).

## Architecture

`bootstrap.sh` (curl-able entry: installs CLT, clones repo, hands off) → `install.sh` (all logic lives here as `comp_*` functions) → `Brewfile` (apps for the `apps` component) + `config/` and `home/` (the dotfiles).

Core mechanics in `install.sh` that everything relies on:

- **`link()`** symlinks a repo path into `$HOME`, backing up any existing real file to `name.bak-<timestamp>` first. Because configs are symlinks, editing `~/.config/ghostty/...` edits this repo's working tree — live-machine tweaks show up as git diffs here, and config-only changes need no reinstall on other machines (just commit/push, `git pull` there).
- **Idempotency is a hard invariant.** Every component must be safely re-runnable: `brew_install` skips installed packages, `clone_if_absent`, `ensure_local_block` appends to `~/.zshrc.local` once keyed by a marker comment. Keep this property when editing components.
- **`~/.zshrc.local`** (untracked, sourced at the end of the tracked `.zshrc`) is where all machine-specific state goes: conda/nvm/grok init blocks, secrets, work paths. The tracked `.zshrc` must stay portable across machines and people.
- **Never runs as root**; Apple Silicon only, Homebrew assumed at `/opt/homebrew`.

## Gotchas / invariants

- **herdr is linked file-level, not directory-level**: `~/.config/herdr` holds runtime state (sockets, logs, session.json), so only `config.toml` is symlinked. herdr's in-app settings (`ctrl+b s`) write through the symlink — TUI changes appear as diffs in `config/herdr/config.toml`.
- **lanna-tone theme copies are generated, not sources.** Source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme); edit there and run `./scripts/sync-theme.sh` — never hand-edit the copies under `config/*/themes/`.
- **`comp_agents` merges, never overwrites**: `~/.claude/settings.json` belongs to Claude Code; only the `statusLine` key is jq-merged in. Preserve that pattern for any future keys.
- **grok's installer appends to `~/.zshrc`** (which is our symlinked tracked file); `comp_agents` strips that block back out of the repo copy so the canonical init lives only in `~/.zshrc.local`. Watch for similar installer pollution of tracked dotfiles — it shows up as an uncommitted diff on `home/zshrc`.
- **Agent configs stay per-machine.** `~/.codex/config.toml`, Claude/Codex/Grok credentials, and sign-ins are deliberately NOT tracked — the repo is public. Only the statusline script and `statusLine` settings key are shared.
- **App Store apps** (LINE, Amphetamine) are `mas` entries in the Brewfile but installed by `comp_apps`'s own loop, never by `brew bundle` — sign-in can't be pre-checked (attempting an install triggers the macOS auth dialog), so missing apps are attempted only on interactive runs and skipped with a warning otherwise. Xcode is deliberately manual (`mas install 497799835`). Brew casks cover everything else (OrbStack replaces Docker Desktop — do not add Docker Desktop).
- **Ghostty is the only terminal** (Alacritty and zellij removed 2026-08; herdr won the multiplexer trial). Ghostty maps Thai (U+0E00–U+0E7F) to Arundina Sans Mono via `font-codepoint-map`, auto-launches herdr, and pairs stock TokyoNight themes with macOS appearance; lanna-tone survives only as the revert copy in `config/ghostty/themes/`.
- Modes are exactly `full` and `partial`; the old `minimal`/`select` names were removed with no aliases. The old terminal-only preset lives on only as a documented `MAC_SETUP_COMPONENTS="ghostty nvim"` example.

## Adding things

- **App**: `cask "name"` in `Brewfile`, then `./install.sh apps`
- **Dotfile**: add the file under `config/` or `home/`, add a `link` line in the relevant `comp_*` function, re-run that component
- **New component**: `comp_<name>()` + a case entry in `run_component`, `choose_components`, and the mode presets; update the README tables
- **macOS tweak**: edit `comp_macos`

The README's "Updating other machines" table maps change types to the component to re-run — keep it accurate when changing the installer.
