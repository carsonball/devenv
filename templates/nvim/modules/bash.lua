-- Managed by devenv (bash module): LazyVim has no shell extra, so wire it up here.
return {
  { "nvim-treesitter/nvim-treesitter", opts = { ensure_installed = { "bash" } } },
  {
    "neovim/nvim-lspconfig",
    opts = { servers = { bashls = { filetypes = { "sh", "bash", "zsh" } } } },
  },
  { "mason-org/mason.nvim", opts = { ensure_installed = { "shellcheck", "shfmt" } } },
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { sh = { "shfmt" }, bash = { "shfmt" } }, formatters = { shfmt = { prepend_args = { "-i", "2", "-ci" } } } },
  },
}
