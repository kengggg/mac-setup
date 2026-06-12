-- ~/.config/nvim/init.lua
-- Hand-rolled, minimal-but-productive Neovim config (a VS Code replacement).
-- Plugins managed by lazy.nvim. Read top-to-bottom; each section is labelled.
-- Your IDE = Alacritty (window) + zellij (panes/terminals) + nvim (editing/LSP).
-- That's why there's no terminal plugin here: use zellij splits instead.

--------------------------------------------------------------------------------
-- 1. Leader key  (must be set BEFORE plugins load)
--------------------------------------------------------------------------------
vim.g.mapleader = " "         -- Space
vim.g.maplocalleader = " "

--------------------------------------------------------------------------------
-- 2. Core options  (ported from your ~/.vimrc, expanded for an IDE)
--------------------------------------------------------------------------------
local opt = vim.opt
opt.number = true             -- absolute number on current line
opt.relativenumber = true     -- relative numbers elsewhere (fast j/k jumps)
opt.mouse = "a"               -- mouse: scroll, select, resize splits
opt.clipboard = "unnamedplus" -- share the macOS system clipboard
opt.breakindent = true        -- wrapped lines keep their indent
opt.undofile = true           -- persistent undo (nvim stores it under stdpath)
opt.ignorecase = true         -- case-insensitive search...
opt.smartcase = true          -- ...unless the query has a capital
opt.signcolumn = "yes"        -- stable gutter (git/diagnostic signs)
opt.updatetime = 250          -- snappier diagnostics / git signs
opt.timeoutlen = 400          -- how long which-key waits before popping up
opt.splitright = true         -- vertical splits open to the right
opt.splitbelow = true         -- horizontal splits open below
opt.cursorline = true         -- highlight the current line
opt.scrolloff = 8             -- keep context around the cursor
opt.termguicolors = true      -- 24-bit color (needed for the theme/treesitter)
opt.expandtab = true          -- tabs -> spaces
opt.tabstop = 4
opt.shiftwidth = 4
opt.softtabstop = 4
opt.smartindent = true
opt.inccommand = "split"      -- live preview of :substitute

--------------------------------------------------------------------------------
-- 3. Basic keymaps  (LSP-specific maps are set on attach, in the LSP section)
--------------------------------------------------------------------------------
local map = vim.keymap.set
map("n", "<leader><CR>", "<cmd>nohlsearch<CR>", { desc = "Clear search highlight" })
map("n", "<leader>w", "<cmd>write<CR>", { desc = "Write/save file" })
map("n", "<leader>q", "<cmd>bdelete<CR>", { desc = "Close buffer" })
-- Buffer (tab) navigation, VS Code style
map("n", "<S-l>", "<cmd>bnext<CR>", { desc = "Next buffer" })
map("n", "<S-h>", "<cmd>bprevious<CR>", { desc = "Previous buffer" })
-- Move between splits with Ctrl + h/j/k/l
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window down" })
map("n", "<C-k>", "<C-w>k", { desc = "Window up" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

--------------------------------------------------------------------------------
-- 4. Bootstrap lazy.nvim  (auto-clones itself on first launch)
--------------------------------------------------------------------------------
local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
  vim.fn.system({
    "git", "clone", "--filter=blob:none",
    "https://github.com/folke/lazy.nvim.git", "--branch=stable", lazypath,
  })
end
vim.opt.rtp:prepend(lazypath)

--------------------------------------------------------------------------------
-- 5. Plugins
--------------------------------------------------------------------------------
require("lazy").setup({
  -- Theme ---------------------------------------------------------------------
  {
    "folke/tokyonight.nvim",
    priority = 1000,            -- load before everything else
    config = function()
      require("tokyonight").setup({ style = "night" })
      vim.cmd.colorscheme("tokyonight")
    end,
  },

  -- Icons (shared dependency) -------------------------------------------------
  { "nvim-tree/nvim-web-devicons", lazy = true },

  -- Treesitter: accurate highlighting -----------------------------------------
  -- Uses the `main` branch (rewritten for Neovim 0.11+). The archived `master`
  -- branch crashes on 0.12 injection parsing. On `main`, parser install is
  -- explicit and highlighting is started per-buffer via core's vim.treesitter.
  {
    "nvim-treesitter/nvim-treesitter",
    branch = "main",
    build = ":TSUpdate",
    config = function()
      local nts = require("nvim-treesitter")
      local want = {
        "lua", "vim", "vimdoc", "bash", "markdown", "markdown_inline",
        "python", "javascript", "typescript", "tsx", "html", "css", "json",
      }
      -- install only parsers that are missing, so startup stays silent/idempotent
      local have = {}
      for _, l in ipairs(nts.get_installed()) do have[l] = true end
      local missing = vim.tbl_filter(function(l) return not have[l] end, want)
      if #missing > 0 then nts.install(missing) end

      vim.api.nvim_create_autocmd("FileType", {
        callback = function(ev)
          pcall(vim.treesitter.start, ev.buf)  -- highlight if a parser exists
        end,
      })
    end,
  },

  -- Telescope: fuzzy finder (Ctrl+P / global search) --------------------------
  {
    "nvim-telescope/telescope.nvim",
    branch = "0.1.x",
    dependencies = {
      "nvim-lua/plenary.nvim",
      { "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
    },
    config = function()
      local tb = require("telescope.builtin")
      require("telescope").setup({})
      pcall(require("telescope").load_extension, "fzf")
      map("n", "<leader>ff", tb.find_files, { desc = "Find files" })
      map("n", "<leader>fg", tb.live_grep, { desc = "Grep in project" })
      map("n", "<leader>fb", tb.buffers, { desc = "Open buffers" })
      map("n", "<leader>fh", tb.help_tags, { desc = "Help tags" })
      map("n", "<leader>fd", tb.diagnostics, { desc = "Diagnostics list" })
    end,
  },

  -- File explorer sidebar -----------------------------------------------------
  {
    "nvim-neo-tree/neo-tree.nvim",
    branch = "v3.x",
    dependencies = { "nvim-lua/plenary.nvim", "MunifTanjim/nui.nvim", "nvim-tree/nvim-web-devicons" },
    config = function()
      require("neo-tree").setup({ close_if_last_window = true })
      map("n", "<leader>e", "<cmd>Neotree toggle<CR>", { desc = "Toggle file explorer" })
    end,
  },

  -- Completion ----------------------------------------------------------------
  {
    "saghen/blink.cmp",
    version = "1.*",            -- uses a prebuilt fuzzy-matcher binary (no cargo)
    opts = {
      keymap = { preset = "enter" },   -- Enter accepts; Tab navigates snippets
      appearance = { nerd_font_variant = "mono" },
      sources = { default = { "lsp", "path", "snippets", "buffer" } },
    },
  },

  -- LSP + Mason (auto-installs language servers) ------------------------------
  {
    "neovim/nvim-lspconfig",
    dependencies = {
      { "mason-org/mason.nvim", config = true },
      "mason-org/mason-lspconfig.nvim",
      "saghen/blink.cmp",
    },
    config = function()
      -- Give every server the completion capabilities from blink.cmp
      vim.lsp.config("*", { capabilities = require("blink.cmp").get_lsp_capabilities() })

      local servers = {
        "lua_ls",                          -- Lua
        "pyright", "ruff",                 -- Python (types + lint/format)
        "ts_ls", "html", "cssls", "jsonls",-- JS/TS + web
      }
      require("mason-lspconfig").setup({
        ensure_installed = servers,
        -- Enable our servers explicitly rather than auto-enabling every
        -- installed mason package (which would wrongly start formatters
        -- like stylua that happen to ship an lsp/ config).
        automatic_enable = false,
      })
      vim.lsp.enable(servers)

      -- Handy LSP keymaps, set only once a server attaches to a buffer.
      -- (nvim 0.11+ already provides grn=rename, gra=code action, grr=refs, K=hover.)
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(ev)
          local o = { buffer = ev.buf }
          map("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", o, { desc = "Go to definition" }))
          map("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", o, { desc = "Go to declaration" }))
          map("n", "<leader>ca", vim.lsp.buf.code_action, vim.tbl_extend("force", o, { desc = "Code action" }))
          map("n", "<leader>rn", vim.lsp.buf.rename, vim.tbl_extend("force", o, { desc = "Rename symbol" }))
        end,
      })
    end,
  },

  -- Formatting (format-on-save) -----------------------------------------------
  {
    "stevearc/conform.nvim",
    opts = {
      format_on_save = { timeout_ms = 1000, lsp_format = "fallback" },
      formatters_by_ft = {
        lua = { "stylua" },
        python = { "ruff_format" },
        javascript = { "prettier" },
        typescript = { "prettier" },
        typescriptreact = { "prettier" },
        html = { "prettier" },
        css = { "prettier" },
        json = { "prettier" },
      },
    },
  },
  -- Ensure the CLI formatters that aren't language servers are installed too.
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    config = function()
      require("mason-tool-installer").setup({ ensure_installed = { "stylua", "prettier" } })
    end,
  },

  -- Git signs in the gutter + hunk actions ------------------------------------
  { "lewis6991/gitsigns.nvim", opts = {} },

  -- Statusline ----------------------------------------------------------------
  {
    "nvim-lualine/lualine.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = { options = { theme = "tokyonight", globalstatus = true } },
  },

  -- Buffer tabs along the top -------------------------------------------------
  {
    "akinsho/bufferline.nvim",
    dependencies = { "nvim-tree/nvim-web-devicons" },
    opts = {},
  },

  -- Keybinding hints popup ("guiding commands") ------------------------------
  { "folke/which-key.nvim", event = "VeryLazy", opts = {} },

  -- Auto-close brackets/quotes -------------------------------------------------
  { "windwp/nvim-autopairs", event = "InsertEnter", opts = {} },

  -- In-buffer markdown rendering (no browser; uses the treesitter parser) ------
  {
    "MeanderingProgrammer/render-markdown.nvim",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    ft = { "markdown" },
    -- 'trimmed' shrinks cell padding so wide tables fit the window instead of
    -- overflowing and wrapping (which scrambles the rendered overlay).
    opts = { pipe_table = { cell = "trimmed" } },
    keys = {
      { "<leader>tm", "<cmd>RenderMarkdown toggle<cr>", desc = "Toggle markdown render" },
    },
  },

  -- Live browser preview for markdown (real HTML; good for very wide tables,
  -- mermaid diagrams, etc.). Uses deno to build its preview server.
  {
    "toppair/peek.nvim",
    ft = { "markdown" },
    build = "deno task --quiet build:fast",
    config = function()
      local peek = require("peek")
      peek.setup()
      vim.api.nvim_create_user_command("PeekOpen", peek.open, {})
      vim.api.nvim_create_user_command("PeekClose", peek.close, {})
      vim.keymap.set("n", "<leader>mp", function()
        if peek.is_open() then peek.close() else peek.open() end
      end, { desc = "Markdown preview (browser)" })
    end,
  },
}, {
  ui = { border = "rounded" },
  checker = { enabled = false },  -- don't auto-check for plugin updates
})
