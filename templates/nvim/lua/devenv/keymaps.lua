-- Managed by devenv: a few additions on top of LazyVim's keymaps.
local map = vim.keymap.set

-- Keep the cursor centered when paging.
map("n", "<C-d>", "<C-d>zz", { desc = "Scroll down (centered)" })
map("n", "<C-u>", "<C-u>zz", { desc = "Scroll up (centered)" })

-- Paste over a selection without losing what you yanked.
map("x", "<leader>p", [["_dP]], { desc = "Paste without yank" })

-- Move selected lines.
map("v", "J", ":m '>+1<cr>gv=gv", { desc = "Move selection down", silent = true })
map("v", "K", ":m '<-2<cr>gv=gv", { desc = "Move selection up", silent = true })

map("n", "<leader>fX", "<cmd>!chmod +x %<cr>", { desc = "Make file executable", silent = true })

-- Open a tmux session picker for another project without leaving Neovim.
if vim.env.TMUX then
  map("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<cr>", { desc = "Switch project (tmux)" })
end
