-- Invoked by install.sh with MAC_SETUP_PROVISION=1. Fail the process when
-- plugin builds, parser installs, or language-tool installs are incomplete.
local errors = {}
local function stage(name, fn)
  local ok, err = xpcall(fn, debug.traceback)
  if not ok then errors[#errors + 1] = name .. ': ' .. tostring(err) end
end

stage('startup', function()
  assert(vim.v.errmsg == '', 'Neovim startup error: ' .. vim.v.errmsg)
end)

stage('plugins', function()
  local lazy = require('lazy')
  lazy.install({ wait = true, show = false, lockfile = true })
  lazy.restore({ wait = true, show = false, clear = false })
  for name, plugin in pairs(require('lazy.core.config').plugins) do
    assert(plugin._.installed, name .. ' is not installed')
    for _, task in ipairs(plugin._.tasks or {}) do
      assert(not task:has_errors(), name .. ' task failed: ' .. tostring(task.name))
    end
  end
end)

stage('treesitter', function()
  local want = {
    'lua', 'vim', 'vimdoc', 'bash', 'markdown', 'markdown_inline',
    'python', 'javascript', 'typescript', 'tsx', 'html', 'css', 'json',
  }
  local nts = require('nvim-treesitter')
  nts.install(want):wait(600000)
  local installed = {}
  for _, name in ipairs(nts.get_installed()) do installed[name] = true end
  for _, name in ipairs(want) do assert(installed[name], 'missing parser: ' .. name) end
end)

stage('Mason', function()
  local registry = require('mason-registry')
  local want = {
    'lua-language-server', 'pyright', 'ruff', 'marksman',
    'typescript-language-server', 'html-lsp', 'css-lsp', 'json-lsp',
    'stylua', 'prettier',
  }
  local pending, started, failed = 0, false, {}
  registry.refresh(function()
    for _, name in ipairs(want) do
      local ok, pkg = pcall(registry.get_package, name)
      if not ok then
        failed[#failed + 1] = name .. ': unavailable in registry'
      elseif not pkg:is_installed() and not pkg:is_installing() then
        pending = pending + 1
        local launched, err = pcall(function()
          pkg:install(nil, function(success)
            pending = pending - 1
            if not success then failed[#failed + 1] = name .. ': install failed' end
          end)
        end)
        if not launched then
          pending = pending - 1
          failed[#failed + 1] = name .. ': ' .. tostring(err)
        end
      end
    end
    started = true
  end)
  local settled = vim.wait(600000, function()
    if not started or pending ~= 0 then return false end
    for _, name in ipairs(want) do
      local ok, pkg = pcall(registry.get_package, name)
      if ok and pkg:is_installing() then return false end
    end
    return true
  end, 200)
  assert(settled, 'timed out waiting for language tools')
  for _, name in ipairs(want) do
    local ok, pkg = pcall(registry.get_package, name)
    if not ok or not pkg:is_installed() then failed[#failed + 1] = name .. ': not installed' end
  end
  assert(#failed == 0, table.concat(failed, '; '))
end)

if #errors > 0 then
  io.stderr:write('nvim provisioning failed:\n' .. table.concat(errors, '\n') .. '\n')
  vim.cmd('cquit 1')
else
  print('nvim provisioning complete: plugins, parsers and language tools verified')
  vim.cmd('qa!')
end
