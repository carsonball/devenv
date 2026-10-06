-- Managed by devenv: tweaks that apply whatever languages are installed.
return {
  -- Ctrl-h/j/k/l moves across Neovim splits and tmux panes alike.
  {
    "christoomey/vim-tmux-navigator",
    cmd = { "TmuxNavigateLeft", "TmuxNavigateDown", "TmuxNavigateUp", "TmuxNavigateRight", "TmuxNavigatePrevious" },
    keys = {
      { "<c-h>", "<cmd><C-U>TmuxNavigateLeft<cr>", desc = "Go to left split/pane" },
      { "<c-j>", "<cmd><C-U>TmuxNavigateDown<cr>", desc = "Go to lower split/pane" },
      { "<c-k>", "<cmd><C-U>TmuxNavigateUp<cr>", desc = "Go to upper split/pane" },
      { "<c-l>", "<cmd><C-U>TmuxNavigateRight<cr>", desc = "Go to right split/pane" },
      { "<c-\\>", "<cmd><C-U>TmuxNavigatePrevious<cr>", desc = "Go to previous split/pane" },
    },
  },

  -- Same palette as WezTerm and tmux.
  { "folke/tokyonight.nvim", opts = { style = "night" } },

  -- Show dotfiles in the file pickers and explorer (git-ignored files stay hidden).
  {
    "folke/snacks.nvim",
    opts = {
      picker = {
        sources = {
          files = { hidden = true },
          grep = { hidden = true },
          explorer = { hidden = true },
        },
      },
    },
  },
}
