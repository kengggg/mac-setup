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
brew "mas"         # Mac App Store CLI — installs the `mas` entries below

# --- Fonts ---
cask "font-meslo-lg-nerd-font"   # the Nerd Font Ghostty + Powerlevel10k use

# --- Terminal emulator ---
cask "ghostty"                   # terminal with per-script font mapping (Thai via Arundina)

# --- GUI apps -----------------------------------------------------------------
# Find cask names with:  brew search --cask <name>
# Snapshot everything already installed with:  brew bundle dump --file=Brewfile.all

# Browsers & comms
cask "google-chrome"
cask "firefox"
cask "slack"
cask "telegram"
cask "discord"
cask "miro"

# Security & networking
cask "1password"
cask "tailscale-app"

# Dev
cask "visual-studio-code"
cask "datagrip"
cask "dbeaver-community"
cask "orbstack"            # Docker engine + CLI (replaces Docker Desktop)
cask "termius"
cask "codexbar"            # Codex usage in the menu bar

# AI apps
cask "claude"              # Claude desktop app
cask "chatgpt"
cask "ollama-app"

# Office & utilities
cask "microsoft-office"    # Word / Excel / PowerPoint
cask "cleanmymac"

# --- App Store apps (via mas; requires being signed into the App Store) -------
mas "LINE",        id: 539883307
mas "Amphetamine", id: 937984704
mas "Xcode",       id: 497799835
