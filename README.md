# devenv

One command sets up a terminal dev environment built around **WezTerm**, **tmux**
and **LazyVim**, with language servers, formatters, linters, debuggers and test
runners for the languages and tools you name. Every package installed and every
file touched is recorded, and any of it can be undone.

```sh
devenv install go docker k8s ts claude
devenv status            # everything devenv changed, grouped by module
devenv undo docker       # take one module back out
devenv undo --all        # put the machine back the way it was
```

## Getting it onto a machine

devenv is plain bash (3.2+, the version macOS ships) and needs nothing but `curl`
and `tar` to bootstrap. It downloads from the public repo
[carsonball/devenv](https://github.com/carsonball/devenv), so a fresh work laptop
needs no GitHub login.

**macOS** (one line in Terminal; it asks for your password once, for Homebrew):

```sh
curl -fsSL https://raw.githubusercontent.com/carsonball/devenv/main/install.sh | bash -s -- go docker k8s ts
```

This installs the Xcode command-line tools and Homebrew if missing, then WezTerm,
tmux, Neovim and everything else. Open WezTerm when it finishes.

**Windows** (PowerShell): tmux has no Windows build, so WezTerm runs on Windows
and everything else runs in WSL (Ubuntu). The bootstrap installs WSL if needed
(Windows may reboot; run it again afterwards), then runs devenv inside Ubuntu,
which installs WezTerm on Windows with `winget` and points it at WSL.

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/carsonball/devenv/main/bootstrap.ps1))) go docker k8s ts
```

From a local copy, without GitHub: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Source . go docker k8s ts`

If WSL and Ubuntu are already set up, you can skip the bootstrap and run the
macOS one-liner inside Ubuntu instead; it installs WezTerm on Windows the same way.

**Linux**: same one-liner as macOS (Debian/Ubuntu get build prerequisites from
apt; elsewhere install curl, git, gcc, make and file first). WezTerm isn't
installed for you on desktop Linux (install it from your distro), but its config
and the Nerd Font are.

After the first run, `devenv` is on your PATH (`~/.local/bin/devenv`), so later
it's just `devenv install python`. `devenv self-update` fetches the latest devenv.

## Commands

| Command                       | Does                                                                 |
|-------------------------------|----------------------------------------------------------------------|
| `devenv install [what...]`    | install the core modules plus the ones you name (re-running refreshes them) |
| `devenv plan [what...]`       | show what `install` would do, change nothing (same as `install --dry-run`) |
| `devenv status`               | installed modules and every recorded change, numbered                |
| `devenv undo <what...>`       | undo modules; or `--id N...`, `--last`, `--run <id>`, `--all`        |
| `devenv diff <N\|path>`       | compare a replaced file with your original                           |
| `devenv log`                  | full history of changes and undos                                    |
| `devenv modules`              | every module and the words that select it                            |
| `devenv doctor`               | check that the tools and configs are wired up                        |
| `devenv self-update`          | update devenv itself                                                 |

Options: `-y` skips the confirmation, `-n`/`--dry-run` changes nothing, `-f`/`--force`
overwrites devenv-written configs you edited (after backing up your copy),
`--no-sync` skips pre-installing Neovim plugins and language tools, and
`--include-homebrew` (with `undo --all`) removes Homebrew too.

Installs run as numbered steps with a live progress line for long ones; the full
output of every command is in `~/.local/state/devenv/runs/<run>.log`.

## What you get

Core, always installed:

| Module    | What                                                                                      |
|-----------|-------------------------------------------------------------------------------------------|
| `cli`     | git, ripgrep, fd, fzf, lazygit, zoxide, eza, bat, jq, gh, tree-sitter, node, python        |
| `shellrc` | `~/.config/devenv/shell.sh` sourced from `.zshrc`/`.bashrc`: PATH, history, aliases, fzf keys, zoxide, starship prompt |
| `tmux`    | `Ctrl-a` prefix, vim-aware pane moves, popups for lazygit and a project picker            |
| `nvim`    | Neovim + LazyVim with debugging (DAP), testing (neotest), JSON/YAML/TOML/Markdown/git, harpoon, surround, inc-rename |
| `wezterm` | WezTerm + JetBrainsMono Nerd Font (Homebrew cask on macOS, winget on Windows), Tokyo Night, opens straight into tmux |

Languages and tools (name a module or any of its aliases, e.g. `ts`, `.tsx`, `kubernetes`):

| Module       | Toolchain from Homebrew                 | In Neovim (LSP, lint/format, debug, test)                       |
|--------------|-----------------------------------------|-----------------------------------------------------------------|
| `go`         | go                                      | gopls, golangci-lint, gofumpt/goimports, delve, neotest-golang  |
| `typescript` | node, pnpm                              | vtsls, eslint, prettier, js-debug-adapter, jest + vitest         |
| `python`     | python 3.13, uv                         | pyright, ruff, debugpy, pytest                                  |
| `rust`       | rustup (stable + rust-analyzer, clippy) | rustaceanvim, clippy, codelldb, crates.nvim                     |
| `docker`     | docker CLI, compose, buildx, lazydocker; Colima on macOS | dockerls, compose LSP, hadolint                  |
| `k8s`        | kubectl, helm, k9s, kubectx, stern      | helm-ls, Kubernetes schemas for manifests                       |
| `terraform`  | terraform, tflint                       | terraform-ls, tflint                                            |
| `java`       | OpenJDK 21, maven, gradle               | jdtls, java-debug, java-test                                    |
| `cpp`        | cmake                                   | clangd, clang-format, codelldb, cmake tools                     |
| `bash`       | shellcheck, shfmt                       | bash-language-server, shellcheck, shfmt                         |
| `sql`        |                                         | vim-dadbod UI + completion, sqlfluff                            |

Optional extras:

| Module   | Installs                                                        | Wiring                                                    |
|----------|-----------------------------------------------------------------|-----------------------------------------------------------|
| `claude` | Claude Code CLI (Anthropic's installer, same on macOS/Linux/WSL) | tmux popup on `Ctrl-a C`; Neovim integration through LazyVim's `ai.claudecode` extra (claudecode.nvim): open Claude in a split, send selections, accept or reject its edits as diffs |

Aliases: `claude-code`, `claudecode`. Run `claude` once afterwards to sign in. Claude
Code keeps itself up to date. devenv never touches your login, settings or
history (`~/.claude`, `~/.claude.json`), not even on undo.

`devenv modules` lists them all with their aliases. The Neovim side is built on
[LazyVim extras](https://www.lazyvim.org/extras), so it follows LazyVim's
upstream defaults. Language servers and tools are pre-installed through Mason
during `devenv install`, so the first `nvim` launch is ready to use.

### Keys worth knowing

| Where   | Keys                         | Does                                                   |
|---------|------------------------------|--------------------------------------------------------|
| tmux    | `Ctrl-a` then `\|` / `-`     | split right / down (in the current directory)          |
| tmux    | `Ctrl-h/j/k/l`               | move between panes **and** Neovim splits               |
| tmux    | `Ctrl-a f`                   | fuzzy-pick a project dir, jump to its own session      |
| tmux    | `Ctrl-a g` / `Ctrl-a t`      | lazygit popup / scratch shell popup                    |
| tmux    | `Alt-1..9`, `Ctrl-a m`       | jump to window, zoom pane                              |
| tmux    | `Ctrl-a H/J/K/L`             | resize pane (repeatable)                               |
| tmux    | `Ctrl-a S` / `Ctrl-a X`      | new named session / kill session                       |
| tmux    | `Ctrl-a r`                   | reload the tmux config                                 |
| tmux    | `Ctrl-a C`                   | Claude Code popup in the current directory (`claude` module) |
| WezTerm | `Cmd-t`, `Cmd-1..9`, `Cmd-d`, `Cmd-Shift-d` (macOS) | tmux new window, select window, split right / down |
| WezTerm | `Cmd-k` / `Cmd-g` (macOS)    | project picker / lazygit                               |
| WezTerm | `Ctrl-Shift-t`               | a plain shell tab without tmux                         |
| WezTerm | `Ctrl-Shift-f`               | toggle full screen                                     |
| Neovim  | `Space` (wait)               | which-key menu of everything                           |
| Neovim  | `Space t t` / `Space t r`    | run tests in file / nearest test                       |
| Neovim  | `Space d b` / `Space d c`    | breakpoint / start or continue debugging               |
| Neovim  | `Space c f`, `Space c a`     | format, code actions                                   |
| Neovim  | `Space g g`                  | lazygit                                                |
| Neovim  | `Ctrl-f`                     | switch project (tmux session picker)                   |
| Neovim  | `Space a c` / `Space a s`    | toggle Claude / send selection to it (`claude` module) |
| Neovim  | `Space a a` / `Space a d`    | accept / reject the diff Claude proposed               |
| shell   | `Ctrl-r`, `Ctrl-t`, `z dir`  | fuzzy history, fuzzy file, jump to a frequent dir      |

**Clipboard.** Yanks in Neovim (`"+y`, or `y` with LazyVim's default
`clipboard=unnamedplus`) and in tmux copy mode or a mouse drag land in the system
clipboard, and `Ctrl-Shift-v` (`Cmd-v` on macOS) pastes from it. On Windows the
tmux side goes through WezTerm (OSC 52); Neovim uses `pbcopy`/`pbpaste`, which
devenv installs in WSL with the same meaning as on macOS (`git diff | pbcopy`,
`pbpaste > notes.txt`). They keep non-ASCII text intact and convert line endings
(CRLF on Windows, LF in WSL); `clip.exe` mangles anything outside the ANSI code
page. Hold `Shift` while dragging to select with WezTerm instead of tmux.

In Claude Code, `Ctrl-j` always adds a new line; `Shift-Enter` does too where the
terminal passes it through (devenv turns on tmux's extended keys for that).

## Tracing and undoing

Everything devenv does is written to `~/.local/state/devenv/manifest.tsv`, one
line per change, and to an append-only `history.log`:

```text
$ devenv status
go
  #17   installed formula          go
nvim
  #36   replaced (original saved)  ~/.config/nvim (original: ~/.local/state/devenv/backups/20261006-001635/home/.config/nvim)
  #37   created directory          ~/.config/nvim
  ...
```

Rules it follows:

- **Packages** are recorded only if devenv installed them. Something you already
  had (from Homebrew, nvm, apt, Docker Desktop...) is used as is and never removed.
- **Existing files are never deleted.** A config devenv replaces (your old
  `~/.config/nvim`, `~/.tmux.conf`, `~/.wezterm.lua`) is moved into
  `~/.local/state/devenv/backups/<run>/` and put back on undo.
- **Your rc files are only appended to**, inside a marked
  `# >>> devenv >>>` block; undo removes exactly that block.
- **Your edits win.** If you edit a file devenv wrote, re-running devenv leaves it
  alone (`--force` overwrites it after backing up your copy), and undo saves your
  edited copy to the backups instead of deleting it.
- **Your Claude Code login stays yours.** `~/.claude` and `~/.claude.json` are
  never recorded, so no undo removes them.
- **Configs follow modules.** Undoing `docker` uninstalls its packages, removes its
  LazyVim extra and shell bits, and keeps any package another module still needs.

Undo by module (`devenv undo k8s`), by change (`devenv undo --id 17 18`), by run
(`devenv undo --last`, `--run <id>`) or entirely (`devenv undo --all`). Undoing a
core module (say `tmux`) also undoes what depends on it, and devenv won't add it
back until you ask for it by name. `devenv plan <what>` shows what an install
would do without changing anything, and `devenv diff <N|path>` compares a
replaced file with your original. Homebrew itself is only removed with
`devenv undo --all --include-homebrew`.

## Customising

devenv-written files say so in their header. Put your own changes where devenv
never writes:

| Tool    | Your file                                                   |
|---------|-------------------------------------------------------------|
| Neovim  | `~/.config/nvim/lua/plugins/*.lua`, `lua/config/{options,keymaps,autocmds}.lua` |
| tmux    | `~/.config/tmux/local.conf`                                 |
| WezTerm | `~/.config/wezterm/local.lua` (return `function(config) ... end`) |
| shell   | `~/.config/devenv/local.sh`                                 |

## Adding a module

Drop a `modules/<name>.conf` (plain `key=value`: `desc`, `aliases`, `requires`,
`brew`, `cask`, `winget`, `extras`, `notes`, each with optional `_darwin`, `_linux`,
`_wsl` or `_desktoplinux` variants; see the top of `lib/modules.sh`). Optionally add
`templates/nvim/modules/<name>.lua` (Neovim specs), `templates/shell/<name>.sh`
(shell snippet), `templates/tmux/modules/<name>.conf` (tmux bindings) and a
`hook_<name>` function in `lib/hooks.sh` for anything beyond packages (the
`claude` module's installer is one). Whatever a hook changes must go through the
recording helpers in `lib/files.sh` so undo can reverse it. For example, Ruby:

```ini
desc=Ruby: ruby-lsp, rubocop, debug adapter
aliases=rb .rb rails
requires=nvim
brew=ruby
extras=lang.ruby
```

## Design notes

- **bash, not a compiled binary**: nothing to build or download per platform; a
  fresh Mac already has bash 3.2, curl and tar. The code avoids bash 4 features and
  GNU-only flags so the same script runs on macOS, Linux and WSL.
- **Homebrew on every platform**: one set of package names, current versions (the
  Neovim in Ubuntu's apt is too old for LazyVim), and clean per-package uninstall.
- **Colima, not Docker Desktop, on macOS**: no licence question on a work machine.
- **WSL on Windows**: tmux needs a Unix; WezTerm stays native for proper
  rendering and clipboard. Neovim reaches the Windows clipboard through
  PowerShell (`pbcopy`/`pbpaste`), not `clip.exe`, which can't take UTF-8. WezTerm
  pastes into WSL with Unix newlines, so no stray `^M` characters.
- **Quiet screen, full log**: installs are numbered steps (`[2/5] Installing packages`).
  Long commands show one live line with a progress bar where the count is known
  (packages, language tools, parsers) or a spinner, elapsed time and latest activity
  where it isn't. Their full output goes to `~/.local/state/devenv/runs/<run>.log`.
  Without a terminal, or with `DEVENV_PLAIN=1`, you get plain lines instead.

## Repository layout

```text
bin/devenv            the CLI
lib/                  manifest, tracked file ops, packages, rendering, undo
lib/mason_install.lua headless Mason pre-install
modules/*.conf        one file per module
templates/            WezTerm, tmux, Neovim and shell configs
install.sh            curl-able bootstrap (macOS, Linux, WSL)
bootstrap.ps1         Windows bootstrap (WSL + WezTerm)
tests/run.sh          end-to-end tests in a throwaway $HOME with fake brew, winget and curl
```

Run the tests with `tests/run.sh` (add `-v` for detail). They never touch the real
machine.

## License

[MIT](LICENSE). devenv installs software and changes files on your machine; it comes with no warranty, so read what `devenv plan` shows before you run it.
