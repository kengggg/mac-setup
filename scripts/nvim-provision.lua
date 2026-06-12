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

-- 2. Mason servers + formatters (must match init.lua's server list + tools)
local registry = require("mason-registry")
local want = {
  "lua-language-server", "pyright", "ruff",
  "typescript-language-server", "html-lsp", "css-lsp", "json-lsp",
  "stylua", "prettier",
}
local function ensure()
  for _, name in ipairs(want) do
    local ok, pkg = pcall(registry.get_package, name)
    if ok and not pkg:is_installed() then pkg:install() end
  end
end
registry.refresh(function() ensure() end)
vim.wait(600000, function()
  for _, name in ipairs(want) do
    local ok, pkg = pcall(registry.get_package, name)
    if not (ok and pkg:is_installed()) then return false end
  end
  return true
end, 1000)

print("nvim provisioning complete")
