-- Exercise provisioning success/failure without installing plugins or tools.
local original_cmd, original_wait = vim.cmd, vim.wait
local cases = { 'success', 'startup', 'plugin-build', 'parser', 'mason-failure', 'registry', 'timeout', 'already-installing' }
for _, scenario in ipairs(cases) do
  vim.v.errmsg = scenario == 'startup' and 'broken plugin config' or ''
  local exit_command, parsers, calls = nil, {}, 0
  vim.cmd = function(command) exit_command = command end
  vim.wait = function(_, predicate)
    if scenario == 'timeout' then return false end
    -- An already-running installer must be awaited, not launched twice.
    local ready = predicate()
    if scenario == 'already-installing' then
      assert(not ready, 'must wait for existing install')
      calls = 1
      return predicate()
    end
    return ready
  end
  package.loaded.lazy = {
    install = function(opts) assert(opts.wait and opts.lockfile) end,
    restore = function(opts) assert(opts.wait and opts.clear == false) end,
  }
  package.loaded['lazy.core.config'] = {
    plugins = { test = { _ = { installed = true, tasks = {
      { name = 'build', has_errors = function() return scenario == 'plugin-build' end },
    } } } },
  }
  package.loaded['nvim-treesitter'] = {
    install = function(want)
      parsers = scenario == 'parser' and {} or want
      return { wait = function() end }
    end,
    get_installed = function() return parsers end,
  }
  local installed = {}
  package.loaded['mason-registry'] = {
    refresh = function(callback) callback() end,
    get_package = function(name)
      if scenario == 'registry' then error('registry unavailable') end
      return {
        is_installed = function() return installed[name] or (scenario == 'already-installing' and calls == 1) end,
        is_installing = function() return scenario == 'already-installing' and calls == 0 end,
        install = function(_, _, callback)
          assert(scenario ~= 'already-installing', 'must not launch existing installer')
          local ok = scenario ~= 'mason-failure'
          installed[name] = ok
          callback(ok)
        end,
      }
    end,
  }
  dofile('scripts/nvim-provision.lua')
  local expected = (scenario == 'success' or scenario == 'already-installing') and 'qa!' or 'cquit 1'
  assert(exit_command == expected, scenario .. ': expected ' .. expected .. ', got ' .. tostring(exit_command))
  print('ok: ' .. scenario)
end
vim.cmd, vim.wait = original_cmd, original_wait
print('8 provisioning scenarios passed')
