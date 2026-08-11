# Brewfile — declarative dependency manifest.
# `brew bundle --file=Brewfile` installs everything below and is idempotent
# (already-installed items are skipped). This is the single place to add new
# tools and GUI apps as your setup grows.

# --- CLI tools (the terminal stack we built) ---
brew "herdr"       # agent multiplexer (auto-launched by Ghostty)
brew "neovim"      # editor
brew "fzf"         # fuzzy finder (Ctrl-R / Ctrl-T in zsh, telescope-fzf in nvim)
brew "fd"          # fast file finder (used by telescope)
brew "ripgrep"     # fast grep (used by telescope live-grep)
brew "tree-sitter-cli" # compiles nvim treesitter parsers (main branch needs the CLI)
brew "lazygit"     # git TUI, floated from nvim with Space g g
brew "jq"          # JSON CLI; required by the Claude Code statusline
brew "eza"         # modern ls (aliased in .zshrc)
# (git comes from Xcode Command Line Tools — a prerequisite, installed before this runs)
brew "gh"          # GitHub CLI
brew "node"        # runtime for some LSP servers (pyright, ts_ls)
brew "mas"         # Mac App Store CLI — only for the MANUAL installs listed at the bottom

# --- Fonts ---
cask "font-meslo-lg-nerd-font"   # the Nerd Font Ghostty + Powerlevel10k use

# --- Terminal emulator ---
cask "ghostty", args: { adopt: true }   # per-script font mapping (Thai via Arundina)

# --- GUI apps -----------------------------------------------------------------
# Find cask names with:  brew search --cask <name>
# Snapshot everything already installed with:  brew bundle dump --file=Brewfile.all
# adopt: take over an identical manually-installed app instead of erroring
# (adoption fails on version mismatch — migrate those with
#  `brew install --cask --force <name>` when you want brew to own them)

# Browsers & comms
cask "google-chrome", args: { adopt: true }
cask "firefox", args: { adopt: true }
cask "slack", args: { adopt: true }
cask "telegram", args: { adopt: true }
cask "discord", args: { adopt: true }
cask "miro", args: { adopt: true }

# Security & networking
cask "1password", args: { adopt: true }
cask "tailscale-app", args: { adopt: true }

# Dev
cask "visual-studio-code", args: { adopt: true }
cask "datagrip", args: { adopt: true }
cask "dbeaver-community", args: { adopt: true }
cask "orbstack", args: { adopt: true }   # Docker engine + CLI (replaces Docker Desktop)
cask "termius", args: { adopt: true }
cask "codexbar", args: { adopt: true }   # Codex usage in the menu bar

# AI apps
cask "claude", args: { adopt: true }     # Claude desktop app
cask "chatgpt", args: { adopt: true }
cask "ollama-app", args: { adopt: true }

# Office & utilities
cask "microsoft-office", args: { adopt: true }   # Word / Excel / PowerPoint
cask "cleanmymac", args: { adopt: true }

# --- App Store apps — NOT installed by this repo -------------------------------
# App Store installs proved too unpredictable to automate (sign-in can't be
# pre-checked, and attempts pop auth dialogs mid-run). When a machine wants
# these, install them manually — signed into the App Store, in a terminal:
#   mas install 539883307    # LINE
#   mas install 937984704    # Amphetamine
#   mas install 497799835    # Xcode (~12GB)
