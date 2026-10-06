-- Run by `devenv install` as: nvim --headless -c "luafile mason_install.lua"
-- Loads the plugins that make LazyVim install language servers, formatters,
-- linters, debug adapters and treesitter parsers, then waits for them so the
-- first interactive launch is ready to go. Exits non-zero if anything failed.

local timeout_ms = tonumber(vim.env.DEVENV_MASON_TIMEOUT or "") or 20 * 60 * 1000
local function say(msg)
  io.stdout:write("[devenv] " .. msg .. "\n")
end

local ok, lazy = pcall(require, "lazy")
if not ok then
  say("lazy.nvim is not available; skipping tool install")
  os.exit(1)
end

-- These configs kick off the installs (LazyVim's mason, lspconfig and dap setups).
lazy.load({ plugins = { "mason.nvim" } })
pcall(lazy.load, { plugins = { "nvim-lspconfig" } })
pcall(lazy.load, { plugins = { "nvim-dap" } })

local registry = require("mason-registry")
local failed = {}

-- Make sure the registry itself loaded; without it nothing can install.
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

-- What LazyVim was asked to install outside of LSP servers.
local wanted = {}
local plugin = require("lazy.core.config").plugins["mason.nvim"]
if plugin then
  wanted = require("lazy.core.plugin").values(plugin, "opts", false).ensure_installed or {}
end
registry:on("package:install:failed", function(pkg)
  failed[#failed + 1] = pkg.name
end)

-- Language servers: LazyVim hands these to mason-lspconfig, which only installs
-- once a matching file is opened. Install the enabled ones explicitly.
local lsp_plugin = require("lazy.core.config").plugins["nvim-lspconfig"]
local ok_map, mappings = pcall(function()
  return require("mason-lspconfig.mappings").get_mason_map().lspconfig_to_package
end)
if lsp_plugin and ok_map then
  local servers = require("lazy.core.plugin").values(lsp_plugin, "opts", false).servers or {}
  for server, sopts in pairs(servers) do
    local pkg_name = mappings[server]
    if server ~= "*" and pkg_name and type(sopts) == "table" and sopts.enabled ~= false and sopts.mason ~= false then
      wanted[#wanted + 1] = pkg_name
    end
  end
end
for _, name in ipairs(wanted) do
  local ok_pkg, pkg = pcall(registry.get_package, name)
  if ok_pkg and not pkg:is_installed() and not pkg:is_installing() then
    pkg:install()
  end
end

-- Wait for the registry refresh and the installs it queues to start, then
-- for every running install to finish.
local function installing()
  local n = {}
  for _, pkg in ipairs(registry.get_all_packages()) do
    if pkg:is_installing() then
      n[#n + 1] = pkg.name
    end
  end
  return n
end

vim.wait(15000, function()
  return #installing() > 0
end, 500)

local last = ""
local done = vim.wait(timeout_ms, function()
  local busy = installing()
  local line = table.concat(busy, ", ")
  if line ~= last and line ~= "" then
    say("installing: " .. line)
  end
  last = line
  return #busy == 0
end, 1000)

-- Treesitter parsers (LazyVim starts these async on load; wait for them here).
local ts_ok, ts = pcall(require, "nvim-treesitter")
local ts_plugin = require("lazy.core.config").plugins["nvim-treesitter"]
if ts_ok and ts.install and ts_plugin then
  local langs = require("lazy.core.plugin").values(ts_plugin, "opts", false).ensure_installed or {}
  say("installing treesitter parsers: " .. #langs)
  local ok_wait, res = pcall(function()
    return ts.install(langs, { summary = true }):wait(timeout_ms)
  end)
  if not ok_wait or res == false then
    failed[#failed + 1] = "treesitter parsers"
  end
end

local installed = registry.get_installed_package_names()
table.sort(installed)
say("installed: " .. table.concat(installed, ", "))
for _, name in ipairs(wanted) do
  if not vim.tbl_contains(installed, name) and not vim.tbl_contains(failed, name) then
    failed[#failed + 1] = name
  end
end
if not done then
  say("timed out waiting for: " .. last)
  os.exit(1)
elseif #failed > 0 then
  say("failed: " .. table.concat(failed, ", "))
  os.exit(1)
else
  os.exit(0)
end
