# devenv

A CLI that sets up a terminal dev environment built around **WezTerm**, **tmux**
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

Two steps: put devenv on the machine, then tell it what to install. The first
step installs nothing but devenv itself (`~/.local/share/devenv`, linked as
`~/.local/bin/devenv`). It downloads from the public repo
[carsonball/devenv](https://github.com/carsonball/devenv); no GitHub login needed.

**1. Get devenv.**

macOS and Linux, in a terminal:

```sh
curl -fsSL https://raw.githubusercontent.com/carsonball/devenv/main/install.sh | bash
```

Windows, in PowerShell: tmux has no Windows build, so WezTerm runs on Windows
and everything else runs in WSL (Ubuntu). The bootstrap installs WSL if needed
(Windows may reboot; run it again afterwards), then puts devenv inside Ubuntu.
If WSL and Ubuntu are already set up, you can run the line above inside Ubuntu
instead.

```powershell
& ([scriptblock]::Create((irm https://raw.githubusercontent.com/carsonball/devenv/main/bootstrap.ps1)))
```

From a local copy, without GitHub: `powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Source .`

**2. Install.** In the same terminal (on Windows, in Ubuntu). If `devenv` isn't
found yet, use `~/.local/bin/devenv`; the install puts it on your PATH.

```sh
devenv modules                   # what's available
devenv plan go docker            # what it would change, nothing installed
devenv install go docker         # the core (see What you get) plus go and docker
```

- **macOS**: installs the Xcode command-line tools and Homebrew if missing (asks
  for your password once), then WezTerm, tmux, Neovim and the rest.
- **Windows**: installs WezTerm with `winget` and points it at WSL.
- **Linux**: Debian/Ubuntu get build prerequisites from apt; elsewhere install
  curl, git, gcc, make and file first. Install WezTerm from your distro; devenv
  writes its config and the Nerd Font.

Open WezTerm when it finishes.

## Commands

| Command                     | Does                                                                                         |
| --------------------------- | -------------------------------------------------------------------------------------------- |
| `devenv install [what...]`  | install the core modules plus the ones you name (re-running repairs them; it never upgrades) |
| `devenv plan [what...]`     | show what `install` would do, change nothing (same as `install --dry-run`)                   |
| `devenv status`             | installed modules and every recorded change, numbered                                        |
| `devenv outdated [what...]` | packages devenv installed that have newer versions, installed vs latest                      |
| `devenv update [what...]`   | install those newer versions                                                                 |
| `devenv undo <what...>`     | undo modules; or `--id N...`, `--last`, `--run <id>`, `--all`                                |
| `devenv diff <N\|path>`     | compare a replaced file with your original                                                   |
| `devenv log`                | full history of changes and undos                                                            |
| `devenv modules`            | every module and the words that select it                                                    |
| `devenv doctor`             | check that the tools and configs are wired up                                                |
| `devenv self-update`        | update devenv itself                                                                         |

Options:

- `-y` skips the confirmation.
- `-n`/`--dry-run` changes nothing.
- `-s`/`--step` asks before each command and file change: `y` does it, `n` skips it, `q` skips it and the rest. Skipped steps are not recorded, and the next `devenv install` offers them again.
- `-f`/`--force` overwrites devenv-written configs you edited, after backing up your copy.
- `--no-sync` skips Neovim plugins and language tools (`install`, `outdated`, `update`).
- `--include-homebrew` (with `undo --all`) removes Homebrew too.

`outdated` and `update` cover only what devenv installed (Homebrew, winget,
rustup, Neovim plugins, Mason tools). Updates aren't recorded, so undo removes a
package but can't downgrade it.

## What you get

Core, always installed:

| Module    | What                                                                                                                                                                                                       |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `cli`     | git, ripgrep, fd, fzf, lazygit, zoxide, yazi, eza, bat, jq, gh, tree-sitter, node, python                                                                                                                  |
| `shellrc` | `~/.config/devenv/shell.sh` sourced from `.zshrc`/`.bashrc`: PATH, history, aliases, fzf keys, zoxide, `y` (yazi), starship prompt                                                                         |
| `tmux`    | `Ctrl-a` prefix, vim-aware pane moves, popups for lazygit and a project picker                                                                                                                             |
| `nvim`    | Neovim + LazyVim with debugging (DAP), testing (neotest), JSON/YAML/TOML/Markdown/git, harpoon, surround, inc-rename, overseer (task runner). Mason's tools (e.g. golangci-lint) are also on the shell PATH, after everything else |
| `wezterm` | WezTerm + JetBrainsMono Nerd Font (Homebrew cask on macOS, winget on Windows), Tokyo Night, opens straight into tmux                                                                                       |

Languages and tools (name a module or any of its aliases, e.g. `ts`, `.tsx`, `kubernetes`):

| Module       | Toolchain from Homebrew                                  | In Neovim (LSP, lint/format, debug, test)                      |
| ------------ | -------------------------------------------------------- | -------------------------------------------------------------- |
| `go`         | go                                                       | gopls, golangci-lint, gofumpt/goimports, delve, neotest-golang |
| `typescript` | node, pnpm                                               | vtsls, eslint, prettier, js-debug-adapter, jest + vitest       |
| `python`     | python 3.13, uv                                          | pyright, ruff, debugpy, pytest                                 |
| `rust`       | rustup (stable + rust-analyzer, clippy)                  | rustaceanvim, clippy, codelldb, crates.nvim                    |
| `docker`     | docker CLI, compose, buildx, lazydocker; Colima on macOS | dockerls, compose LSP, hadolint                                |
| `k8s`        | kubectl, helm, k9s, kubectx, stern                       | helm-ls, Kubernetes schemas for manifests                      |
| `terraform`  | terraform                                                | terraform-ls, tflint                                           |
| `java`       | OpenJDK 21, maven, gradle                                | jdtls, java-debug, java-test                                   |
| `cpp`        | cmake                                                    | clangd, clang-format, codelldb, cmake tools                    |
| `bash`       | shellcheck, shfmt                                        | bash-language-server, shellcheck, shfmt                        |
| `sql`        |                                                          | vim-dadbod UI + completion, sqlfluff                           |

Optional extras:

| Module                                 | Installs                                                         | Wiring                                                                                                                                                                               |
| -------------------------------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `claude` (`claude-code`, `claudecode`) | Claude Code CLI (Anthropic's installer, same on macOS/Linux/WSL) | tmux popup on `Ctrl-a C`; Neovim integration through LazyVim's `ai.claudecode` extra (claudecode.nvim): open Claude in a split, send selections, accept or reject its edits as diffs |

Run `claude` once afterwards to sign in. devenv never touches your login,
settings or history (`~/.claude`, `~/.claude.json`), not even on undo.

Add-ons for Claude Code (each brings in `claude`):

| Module                             | What                                                                                                                                                                                                     |
| ---------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `caveman` (`cave`)                 | [caveman](https://github.com/JuliusBrussee/caveman): terse answers (`/caveman`, `/ultracave`, `/caveman off`), `/caveman-commit`, `/caveman-review`                                                      |
| `ponytail`                         | [ponytail](https://github.com/DietrichGebert/ponytail): minimal-code mode (`/ponytail lite\|full\|ultra\|off`), `/ponytail-review`, `/ponytail-audit`                                                    |
| `gopls` (`gopls-lsp`)             | [gopls-lsp](https://github.com/anthropics/claude-plugins-official): Go code intelligence for Claude (definitions, references, diagnostics) through gopls; brings in `go` |
| `lavish` (`lavish-axi`)            | [lavish-axi](https://github.com/kunchenguid/lavish-axi): review agent-written HTML (plans, diagrams) in your browser and send notes back (`/lavish`)                                                     |
| `nomistakes` (`no-mistakes`, `nm`) | [no-mistakes](https://github.com/kunchenguid/no-mistakes): `git push no-mistakes` runs an AI review, tests and lint in a worktree, then opens the PR. Per repo: `no-mistakes init` / `no-mistakes eject` |

Plugins load in the next `claude` session. Undo uses `claude plugin uninstall`;
anything you already had is never removed.

The Neovim side is built on [LazyVim extras](https://www.lazyvim.org/extras), so
it follows LazyVim's upstream defaults. Language servers and tools are
pre-installed through Mason during `devenv install`, so the first `nvim` launch
is ready to use.

### Keys worth knowing

| Where   | Keys                                                | Does                                                         |
| ------- | --------------------------------------------------- | ------------------------------------------------------------ |
| tmux    | `Ctrl-a c`                                          | new window (in the current directory)                        |
| tmux    | `Ctrl-a` then `\|` / `-`                            | split right / down (in the current directory)                |
| tmux    | `Ctrl-h/j/k/l`                                      | move between panes **and** Neovim splits                     |
| tmux    | `Ctrl-a f`                                          | fuzzy-pick a project dir, jump to its own session            |
| tmux    | `Ctrl-a g` / `Ctrl-a t`                             | lazygit popup / scratch shell popup                          |
| tmux    | `Alt-1..9`, `Ctrl-a m`                              | jump to window, zoom pane                                    |
| tmux    | `Ctrl-a H/J/K/L`                                    | resize pane (repeatable)                                     |
| tmux    | `Ctrl-a S` / `Ctrl-a X`                             | new named session / kill session                             |
| tmux    | `Ctrl-a r`                                          | reload the tmux config                                       |
| tmux    | `Ctrl-a C`                                          | Claude Code popup in the current directory (`claude` module) |
| WezTerm | `Cmd-t`, `Cmd-1..9`, `Cmd-d`, `Cmd-Shift-d` (macOS) | tmux new window, select window, split right / down           |
| WezTerm | `Cmd-k` / `Cmd-g` (macOS)                           | project picker / lazygit                                     |
| WezTerm | `Ctrl-Shift-t`                                      | a plain shell tab without tmux                               |
| WezTerm | `Ctrl-Shift-f`                                      | toggle full screen                                           |
| Neovim  | `Space` (wait)                                      | which-key menu of everything                                 |
| Neovim  | `Space t t` / `Space t r`                           | run tests in file / nearest test                             |
| Neovim  | `Space d b` / `Space d c`                           | breakpoint / start or continue debugging                     |
| Neovim  | `Space c f`, `Space c a`                            | format, code actions                                         |
| Neovim  | `Space g g`                                         | lazygit                                                      |
| Neovim  | `Shift-h` / `Shift-l`                               | previous / next open file (buffer)                           |
| Neovim  | `Shift-w`                                           | close the current buffer                                     |
| Neovim  | `Ctrl-[` / `Ctrl-]`                                 | jump back / forward (replaces `Ctrl-o` / `Ctrl-i`)           |
| Neovim  | `Ctrl-f`                                            | switch project (tmux session picker)                         |
| Neovim  | `Space a c` / `Space a s`                           | toggle Claude / send selection to it (`claude` module)       |
| Neovim  | `Space a a` / `Space a d`                           | accept / reject the diff Claude proposed                     |
| shell   | `Ctrl-r`, `Ctrl-t`, `z dir`                         | fuzzy history, fuzzy file, jump to a frequent dir            |

**Clipboard.** Yanks in Neovim and tmux (copy mode or a mouse drag) go to the
system clipboard; `Ctrl-Shift-v` (`Cmd-v` on macOS) pastes. Hold `Shift` while
dragging to select with WezTerm instead of tmux.

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

- **Packages you already had are never removed**; only what devenv installed is recorded.
- **Existing files are never deleted**: replaced configs go to `~/.local/state/devenv/backups/<run>/` and come back on undo.
- **rc files are only appended to**, in a `# >>> devenv >>>` block that undo removes.
- **Your edits win**: re-runs leave edited files alone (unless `--force`), and undo backs them up instead of deleting.
- **Your Claude Code login stays yours**: `~/.claude` and `~/.claude.json` are never recorded.
- **Configs follow modules**: undoing `docker` removes its packages, LazyVim extra and shell bits, keeping packages another module needs.

Undoing a core module (say `tmux`) also undoes what depends on it; devenv won't
re-add it until you name it.

## Customising

devenv-written files say so in their header. Put your own changes where devenv
never writes:

| Tool    | Your file                                                                       |
| ------- | ------------------------------------------------------------------------------- |
| Neovim  | `~/.config/nvim/lua/plugins/*.lua`, `lua/config/{options,keymaps,autocmds}.lua` |
| tmux    | `~/.config/tmux/local.conf`                                                     |
| WezTerm | `~/.config/wezterm/local.lua` (return `function(config) ... end`)               |
| shell   | `~/.config/devenv/local.sh`                                                     |

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
