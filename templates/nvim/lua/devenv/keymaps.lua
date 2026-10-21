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

-- Ctrl-/ toggles comments on a selection. Terminals usually send it as Ctrl-_.
-- Visual only: in normal mode LazyVim uses Ctrl-/ for its terminal.
map("x", "<C-/>", "gc", { desc = "Toggle comment", remap = true })
map("x", "<C-_>", "gc", { desc = "Toggle comment", remap = true })

-- Shift + mouse wheel scrolls sideways: wheel up goes right.
map({ "n", "v", "i" }, "<S-ScrollWheelUp>", "<ScrollWheelRight>", { desc = "Scroll right" })
map({ "n", "v", "i" }, "<S-ScrollWheelDown>", "<ScrollWheelLeft>", { desc = "Scroll left" })

map("n", "<leader>fX", "<cmd>!chmod +x %<cr>", { desc = "Make file executable", silent = true })

-- Open a tmux session picker for another project without leaving Neovim.
if vim.env.TMUX then
  map("n", "<C-f>", "<cmd>silent !tmux neww tmux-sessionizer<cr>", { desc = "Switch project (tmux)" })
end

-- Jumplist on Ctrl-[ / Ctrl-] instead of Ctrl-o / Ctrl-i. Ctrl-[ needs a
-- terminal that sends it apart from Esc (devenv's WezTerm config does).
map("n", "<C-[>", "<C-o>", { desc = "Jump back" })
map("n", "<C-]>", "<C-i>", { desc = "Jump forward" })
map("n", "<C-o>", "<Nop>")
map("n", "<C-i>", "<Nop>")
