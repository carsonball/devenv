-- Run by `devenv outdated` and `devenv update` as:
--   DEVENV_NVIM_MODE=check|update nvim --headless -c "luafile nvim_update.lua"
-- Lists (check) or installs (update) newer versions of Neovim plugins
-- (lazy.nvim) and of the language tools Mason installed. For each one out of
-- date it prints:  [devenv] outdated <plugin|tool> <name> <installed> <latest>
-- Exits non-zero if anything failed.

local update = vim.env.DEVENV_NVIM_MODE == "update"
local timeout_ms = tonumber(vim.env.DEVENV_MASON_TIMEOUT or "") or 20 * 60 * 1000
local function say(msg)
  io.stdout:write("\n[devenv] " .. msg .. "\n")
  io.stdout:flush()
end

local ok, lazy = pcall(require, "lazy")
if not ok then
  say("lazy.nvim is not available")
  os.exit(1)
end
local plugins = require("lazy.core.config").plugins

-- Plugins: lazy.nvim compares each checkout with its branch or version tag upstream.
local function ver(info)
  if not info then
    return "?"
  end
  return info.version and tostring(info.version) or (info.commit or "?"):sub(1, 7)
end
lazy.check({ wait = true, show = false })
local stale = {}
for name, p in pairs(plugins) do
  if p._.updates then
    stale[#stale + 1] = name
    say(("outdated plugin %s %s %s"):format(name, ver(p._.updates.from), ver(p._.updates.to)))
  end
end
if update and #stale > 0 then
  lazy.update({ wait = true, show = false, plugins = stale })
end

-- Mason tools. Set Mason up directly rather than through LazyVim, whose config
-- would also start installing anything missing.
local mason = plugins["mason.nvim"]
if not mason then
  os.exit(0)
end
vim.opt.rtp:prepend(mason.dir)
require("mason").setup()
local registry = require("mason-registry")
local refreshed = false
registry.refresh(function()
  refreshed = true
end)
vim.wait(120000, function()
  return refreshed
end, 200)
if #registry.get_all_package_names() == 0 then
  say("could not load the Mason registry (network or GitHub API rate limit?)")
  os.exit(1)
end

local failed, pending = {}, 0
for _, pkg in ipairs(registry.get_installed_packages()) do
  local have = pkg:get_installed_version()
  local got, latest = pcall(pkg.get_latest_version, pkg)
  if have and got and latest and have ~= latest then
    say(("outdated tool %s %s %s"):format(pkg.name, have, latest))
    if update then
      pending = pending + 1
      pkg:install({ version = latest }, function(success)
        pending = pending - 1
        if not success then
          failed[#failed + 1] = pkg.name
        end
      end)
    end
  end
end
local done = vim.wait(timeout_ms, function()
  return pending == 0
end, 500)
if not done then
  say("timed out updating Mason tools")
  os.exit(1)
elseif #failed > 0 then
  say("failed: " .. table.concat(failed, ", "))
  os.exit(1)
end
os.exit(0)
