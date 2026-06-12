# Brewfile — declarative dependency manifest.
# `brew bundle --file=Brewfile` installs everything below and is idempotent
# (already-installed items are skipped). This is the single place to add new
# tools and GUI apps as your setup grows.

# --- CLI tools (the terminal stack we built) ---
brew "zellij"      # terminal multiplexer
brew "neovim"      # editor
brew "fzf"         # fuzzy finder (Ctrl-R / Ctrl-T in zsh, telescope-fzf in nvim)
brew "fd"          # fast file finder (used by telescope)
brew "ripgrep"     # fast grep (used by telescope live-grep)
brew "tree-sitter-cli" # compiles nvim treesitter parsers (main branch needs the CLI)
brew "lazygit"     # git TUI, floated from nvim with Space g g
brew "eza"         # modern ls (aliased in .zshrc)
# (git comes from Xcode Command Line Tools — a prerequisite, installed before this runs)
brew "gh"          # GitHub CLI (needed to clone this private repo on new machines)
brew "node"        # runtime for some LSP servers (pyright, ts_ls)

# --- Fonts ---
cask "font-meslo-lg-nerd-font"   # the Nerd Font Alacritty + Powerlevel10k use

# --- Terminal emulator ---
cask "alacritty"

# --- GUI apps -----------------------------------------------------------------
# Add the apps you want a resurrected machine to have. Examples (uncomment/add):
# cask "1password"
# cask "slack"
# cask "google-chrome"
# cask "visual-studio-code"
# cask "rectangle"          # window manager
# cask "raycast"            # launcher
#
# Find cask names with:  brew search --cask <name>
# Snapshot everything already installed with:  brew bundle dump --file=Brewfile.all
