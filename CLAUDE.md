# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

Machine setup & resurrection for Apple Silicon Macs — a component-based installer plus the dotfiles it symlinks into place. There is no build or lint; "development" means editing configs/installer and re-running the relevant component. The one test suite is `tests/link-layer.sh` (bash, sandboxed `$HOME` + local bare remote, no brew/network) — run it after touching the link layer, `update`, `doctor` or `bootstrap.sh`, and add a case for any new link-layer behaviour.

**Objective:** make a fresh machine — Keng's own or a second machine for someone else — reproduce this setup with one command, then stay in sync via git. Every machine uses the same model: clone + symlink + `git pull`.

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/kengggg/mac-setup/main/bootstrap.sh)"
```

The repo is public, so this works with no GitHub auth. Modes are `full` (everything) and `partial` (interactive component checklist) — nothing else. `MAC_SETUP_MODE=full` makes it non-interactive; `MAC_SETUP_COMPONENTS="ghostty nvim agents"` runs an exact component list instead, recorded like a partial run so `update` replays it.

## Commands

```sh
./install.sh                     # interactive mode menu (full / partial)
./install.sh --mode full         # everything
./install.sh --mode partial      # component checklist
./install.sh ghostty agents      # run specific components (doesn't change the machine's record)
./install.sh update              # git pull --ff-only, re-exec the pulled script, replay the recorded selection
./install.sh doctor              # read-only health check: pointer, every managed link, git state, herdr
./install.sh relink              # after moving the clone: fix the pointer + adopt links, no installs
./scripts/sync-theme.sh          # pull the lanna-tone theme copy from the canonical theme repo
./tests/link-layer.sh            # link-layer tests (sandboxed; nothing touches the real machine)
```

Components: `ghostty` `nvim` `shell` `devtools` `agents` `apps` `macos` (`claude` is a deprecated alias for `agents`; `alacritty` in an old record runs `ghostty`, which now owns it; the retired `zellij` name warns-then-skips so old machine records keep replaying). `ghostty` = Ghostty + herdr (daily) **and Alacritty (rescue)** — installed together so the rescue terminal is always present; if the alacritty cask can't install (disabled upstream), the component warns and continues (fonts, links, defaults still land) rather than aborting the daily terminal's setup. `agents` = Claude Code (native installer → `~/.local/bin`) + statusline, Codex CLI (brew cask), Grok CLI — deliberately separate from `devtools` (conda+nvm) so a second machine can take one without the other. Runs are recorded to `~/.config/mac-setup/selection` (untracked, per-machine): full by mode name (re-resolved at `update` time, so components later added to full get picked up), partial by exact component list. Records from the retired `minimal`/`select` modes re-prompt once.

## Architecture

`bootstrap.sh` (curl-able entry: installs CLT, clones repo, hands off) → `install.sh` (all logic lives here as `comp_*` functions) → `Brewfile` (apps for the `apps` component) + `config/` and `home/` (the dotfiles).

Core mechanics in `install.sh` that everything relies on:

- **The link layer** (`links` manifest → `ensure_repo_link`, `converge_links`, `link_component`, `doctor`). Every machine has one pointer `~/.config/mac-setup/repo → <clone>`, and every managed dotfile links *through* it, so moving the clone invalidates one symlink, not all of them. The manifest (`links()`, columns: component, repo-relative source, destination under `$HOME`) is the only place links are declared. Every run — any verb except `doctor`, any selection — first re-points the pointer at the clone it runs from, adopts every managed link that is already ours (a symlink whose target ends with the manifest's repo-relative path: pre-pointer direct links, links dangling after a move), writes the `~/.zprofile` guard, and ends with `doctor`. That pass never creates a link and never touches a real file or a foreign symlink; `link_component <comp>` does the creating (backing up a real file to `name.bak-<timestamp>`) and only runs when its component is selected. There is no schema version and no migration step: old-scheme machines, moved clones and fresh machines all converge through the same code. Because configs are symlinks, editing `~/.config/ghostty/...` edits this repo's working tree — live-machine tweaks show up as git diffs here, and config-only changes need no reinstall on other machines (just commit/push, `update` there).
- **`update` pulls, then re-execs.** Bash reads a script incrementally, so `git pull` must not rewrite the running `install.sh`; `update` pulls first and `exec`s the fresh file with `MAC_SETUP_PULLED=1`. The pull is `--ff-only --no-rebase --autostash`: `--no-rebase` because a `pull.rebase=true` config (tools set it per clone) makes git refuse to pull over *any* unstaged change, `--autostash` because nvim writes `lazy-lock.json` through its symlink so the clone is almost never clean. A failed pull (diverged clone, offline) warns and continues on the checked-out code. `doctor` and `relink` never need brew and run before `bootstrap_homebrew`.
- **Idempotency is a hard invariant.** Every component must be safely re-runnable: `brew_install` skips installed packages, `clone_if_absent`, `ensure_local_block` appends to `~/.zshrc.local` once keyed by a marker comment. Keep this property when editing components.
- **Failure isolation.** Each component runs in its own `set -e` subshell: it stops at its first internal error, but the run continues, collects failures, and ends with "components with errors: … — re-run: ./install.sh …" (exit 1). Only `bootstrap_homebrew` is fail-fast — everything needs brew, and it pre-checks that `/opt/homebrew` is writable by the current user (printing the `sudo chown` fix if not).
- **`~/.zshrc.local`** (untracked, sourced at the end of the tracked `.zshrc`) is where all machine-specific state goes: conda/nvm/grok init blocks, secrets, work paths. The tracked `.zshrc` must stay portable across machines and people.
- **Never runs as root, never sudos** — anything needing privileges is printed as an instruction. Apple Silicon only; Homebrew assumed at `/opt/homebrew`.

## Gotchas / invariants

- **Nothing installs from the App Store — ever.** Sign-in can't be pre-checked (attempting an install is what triggers the macOS auth dialog), so automated MAS installs are banned. Do not add `mas "..."` entries to the Brewfile; the manual `mas install` one-liners live there as comments, and the `mas` CLI stays installed as a tool.
- **`comp_apps` converges; it never upgrades or replaces.** `brew bundle install --no-upgrade`, plus a presence probe: any cask whose app already exists in `/Applications` but isn't brew-managed goes into `HOMEBREW_BUNDLE_CASK_SKIP` and is left alone. Casks Homebrew has *disabled* (e.g. alacritty, 2026-09, fails Gatekeeper) are skipped with a warning too — attempting one fails the bundle on every run. Pkg-based casks expose no `.app` artifact — they have an explicit probe table (`microsoft-office`, `tailscale-app`); extend it when adding pkg casks. GUI casks carry `args: { adopt: true }` so identical manual installs get adopted. Bundle failures warn, never abort.
- **herdr is linked file-level, not directory-level**: `~/.config/herdr` holds runtime state (sockets, logs, session.json), so only `config.toml` is symlinked. herdr's in-app settings (`ctrl+b s`) write through the symlink — TUI changes appear as diffs in `config/herdr/config.toml`.
- **The lanna-tone theme copy is generated, not source.** Source of truth is [kengggg/lanna-tone-theme](https://github.com/kengggg/lanna-tone-theme); edit there and run `./scripts/sync-theme.sh` — never hand-edit `config/ghostty/themes/lanna-tone` or `config/alacritty/themes/lanna-tone.toml`.
- **`comp_agents` merges, never overwrites**: `~/.claude/settings.json` belongs to Claude Code; only the `statusLine` key is jq-merged in. Preserve that pattern for any future keys.
- **grok's installer appends to `~/.zshrc`** (our symlinked tracked file); `comp_agents` strips that block back out of the repo copy so the canonical init lives only in `~/.zshrc.local`. Watch for similar installer pollution of tracked dotfiles — it shows up as an uncommitted diff on `home/zshrc`.
- **Agent configs stay per-machine.** `~/.codex/config.toml`, Claude/Codex/Grok credentials, and sign-ins are deliberately NOT tracked — the repo is public. Only the statusline script and `statusLine` settings key are shared.
- **`comp_shell` auto-fixes compaudit findings** (two-account machines leave completion paths owned by another user): flagged symlinks in user-writable dirs are replaced with owned copies. `sudo chown` cannot fix these — macOS App Management blocks writes into other apps' bundles, even for root.
- **Two terminals, two roles.** Ghostty is the daily one: it maps Thai (U+0E00–U+0E7F) to Arundina Sans Mono via `font-codepoint-map`, auto-launches herdr (falling back to a plain login zsh when herdr isn't on PATH, so a missing multiplexer never kills the window), and pairs stock TokyoNight themes with macOS appearance; lanna-tone survives there as the revert copy in `config/ghostty/themes/`. Alacritty is the **rescue** terminal: plain login zsh, nothing auto-launched, its own config (`config/alacritty/`, lanna-tone, same keybinds). Never wire herdr or any auto-launch into Alacritty — its whole point is to work when the Ghostty/herdr side is broken.
- **Retired components leave links behind.** `retired()` in `install.sh` lists their destinations (`~/.config/zellij`). The convergence pass deletes one only when it's a dangling symlink; a real dir or live link is left alone and `doctor` reports it as `stale`. The installer never `brew uninstall`s anything — dropping a retired formula is manual.
- **`bootstrap.sh` honours the repo pointer.** `MAC_SETUP_DEST` wins, then `~/.config/mac-setup/repo`'s target, then `~/Workspaces/mac-setup` for a fresh machine — re-running the one-liner never makes a second clone on a machine that keeps its clone elsewhere. A *dangling* pointer (clone moved without `relink`, or deleted) makes bootstrap stop with instructions instead of silently cloning a second copy into the default path.
- Modes are exactly `full` and `partial`; the old `minimal`/`select` names were removed with no aliases. The old terminal-only preset lives on only as a documented `MAC_SETUP_COMPONENTS="ghostty nvim"` example.

## Adding things

- **App**: `cask "name", args: { adopt: true }` in `Brewfile`, then `./install.sh apps`
- **Dotfile**: add the file under `config/` or `home/`, add a row to the `links()` manifest in `install.sh` (component, source, destination), re-run that component. Nothing else — `relink`, `doctor` and the convergence pass read the manifest.
- **New component**: `comp_<name>()` + a case entry in `run_component`, `choose_components`, and the full-mode preset; update the README tables
- **macOS tweak**: edit `comp_macos`

The README's "Updating other machines" table maps change types to the component to re-run — keep it accurate when changing the installer.
