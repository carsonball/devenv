-- Managed by devenv: rewritten on `devenv install` unless you edit it.
-- Prefer putting overrides in lua/config/options.lua.
local opt = vim.opt

opt.scrolloff = 8 -- keep context around the cursor
opt.sidescrolloff = 8
opt.wrap = false
opt.swapfile = false -- undofile (on in LazyVim) is the safety net
opt.updatetime = 200
opt.spelllang = { "en" }
opt.colorcolumn = "100"
opt.exrc = true -- trust-prompted per-project .nvim.lua

-- Spell-check prose filetypes only.
vim.api.nvim_create_autocmd("FileType", {
  pattern = { "gitcommit", "markdown", "text" },
  callback = function()
    vim.opt_local.spell = true
  end,
})

-- WSL: route the system clipboard through Windows.
if vim.fn.has("wsl") == 1 then
  vim.g.clipboard = {
    name = "WslClipboard",
    copy = { ["+"] = "clip.exe", ["*"] = "clip.exe" },
    paste = {
      ["+"] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r", ""))',
      ["*"] = 'powershell.exe -NoLogo -NoProfile -c [Console]::Out.Write($(Get-Clipboard -Raw).ToString().Replace("`r", ""))',
    },
    cache_enabled = 0,
  }
end
