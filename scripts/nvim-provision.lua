-- Headless provisioning for Neovim: install treesitter parsers and Mason
-- servers/formatters so a freshly-set-up machine is ready without a manual
-- first launch. Run via:
--   nvim --headless -c "luafile scripts/nvim-provision.lua" -c "qa!"
-- (Plugins themselves are installed separately with `Lazy! restore`, which
--  honors lazy-lock.json for reproducible versions.)

-- 1. Treesitter parsers (must match the list in init.lua). nvim-treesitter
--    `main` compiles via the tree-sitter CLI (installed by the Brewfile), and
--    install() is async, so we block on its handle.
local parsers = {
  "lua", "vim", "vimdoc", "bash", "markdown", "markdown_inline",
  "python", "javascript", "typescript", "tsx", "html", "css", "json",
}
pcall(function() require("nvim-treesitter").install(parsers):wait(600000) end)

-- 2. Mason servers + formatters (must match init.lua's server list + tools).
--    The config's mason-lspconfig / mason-tool-installer also start installing
--    on startup, so we must NOT call install() on a package that's already
--    installing (Package:install asserts in that case), and must NOT exit while
--    anything is still installing (qa! would abort it — e.g. prettier). So we
--    wait until every package is installed AND idle, triggering only the ones
--    that are genuinely missing-and-not-already-installing.
-- Run with MAC_SETUP_PROVISION=1 so init.lua's auto-installers stay off and we
-- are the only installer. We install each missing package with a COMPLETION
-- CALLBACK (the authoritative "done" signal — is_installed() flips true before
-- the install handle finishes, which is what aborted prettier before) and wait
-- until every callback has fired.
local registry = require("mason-registry")
local want = {
  "lua-language-server", "pyright", "ruff",
  "typescript-language-server", "html-lsp", "css-lsp", "json-lsp",
  "stylua", "prettier",
}
local pending, started = 0, false
registry.refresh(function()
  for _, name in ipairs(want) do
    local ok, pkg = pcall(registry.get_package, name)
    if ok and not pkg:is_installed() and not pkg:is_installing() then
      pending = pending + 1
      pkg:install(nil, function() pending = pending - 1 end)  -- fires when truly done
    end
  end
  started = true
end)

local settled = vim.wait(600000, function() return started and pending == 0 end, 200)
print("nvim provisioning " .. (settled and "complete" or "timed out (some packages may be unfinished)"))
