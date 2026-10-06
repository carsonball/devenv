# shellcheck shell=bash
# Shared helpers: logging, prompts, platform detection, dry-run aware execution.
# Everything in lib/ must stay compatible with the bash 3.2 that ships with macOS:
# no associative arrays, no mapfile, no ${var,,}, no `set -u` around empty arrays.

if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
  C_RESET=$'\033[0m' C_DIM=$'\033[2m' C_BOLD=$'\033[1m'
  C_RED=$'\033[31m' C_GREEN=$'\033[32m' C_YELLOW=$'\033[33m' C_BLUE=$'\033[34m'
else
  C_RESET='' C_DIM='' C_BOLD='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE=''
fi

log()     { printf '%s\n' "$*" >&2; [ -n "${RUN_LOG:-}" ] && printf '%s\n' "$*" >>"$RUN_LOG"; return 0; }
info()    { log "${C_BLUE}==>${C_RESET} ${C_BOLD}$*${C_RESET}"; }
step()    { log "  ${C_DIM}-${C_RESET} $*"; }
ok()      { log "  ${C_GREEN}✓${C_RESET} $*"; }
warn()    { log "  ${C_YELLOW}!${C_RESET} $*"; }
err()     { log "${C_RED}error:${C_RESET} $*"; }
die()     { err "$*"; exit 1; }

is_dry() { [ "${DRY_RUN:-0}" = 1 ]; }

# Ask a yes/no question. Reads from the terminal even when stdin is a pipe
# (curl ... | bash), and defaults to "no" when there is no terminal at all.
confirm() {
  [ "${ASSUME_YES:-0}" = 1 ] && return 0
  local reply=''
  if [ -r /dev/tty ] && (exec </dev/tty) 2>/dev/null; then
    printf '%s [y/N] ' "$1" >/dev/tty
    read -r reply </dev/tty || reply=''
  else
    warn "no terminal to confirm '$1'; pass --yes to proceed non-interactively"
    return 1
  fi
  case "$reply" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}

# Run a command, or describe it in dry-run mode. Output goes to the run log.
run() {
  if is_dry; then step "${C_DIM}would run:${C_RESET} $*"; return 0; fi
  step "${C_DIM}\$ $*${C_RESET}"
  if [ -n "${RUN_LOG:-}" ]; then
    "$@" >>"$RUN_LOG" 2>&1
  else
    "$@"
  fi
}

# Show paths under $HOME as ~/...
tilde() { case "$1" in "$HOME"/*) printf '~%s\n' "${1#"$HOME"}" ;; *) printf '%s\n' "$1" ;; esac; }

has() { command -v "$1" >/dev/null 2>&1; }

now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

sha_of() {
  [ -f "$1" ] || { echo none; return; }
  if has sha256sum; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1
  fi
}

# Resolve symlinks without GNU readlink -f (macOS < 12.3 lacks it).
resolve_path() {
  local p=$1 dir
  while [ -L "$p" ]; do
    dir=$(cd -P "$(dirname "$p")" && pwd)
    p=$(readlink "$p")
    case "$p" in /*) ;; *) p="$dir/$p" ;; esac
  done
  dir=$(cd -P "$(dirname "$p")" && pwd)
  printf '%s/%s\n' "$dir" "$(basename "$p")"
}

# Reverse lines (tac is not on macOS).
reverse_lines() { awk '{ l[NR] = $0 } END { for (i = NR; i > 0; i--) print l[i] }'; }

# "a b c" contains "b"?
word_in() {
  local needle=$1 w; shift
  # shellcheck disable=SC2048
  for w in $*; do [ "$w" = "$needle" ] && return 0; done
  return 1
}

# --- platform -------------------------------------------------------------

detect_platform() {
  OS=${DEVENV_OS:-}
  if [ -z "$OS" ]; then
    case "$(uname -s)" in
      Darwin) OS=darwin ;;
      Linux)  OS=linux ;;
      *) die "unsupported OS: $(uname -s). On Windows, run bootstrap.ps1 (it sets up WSL)." ;;
    esac
  fi
  ARCH=${DEVENV_ARCH:-$(uname -m)}
  IS_WSL=${DEVENV_WSL:-0}
  if [ "$OS" = linux ] && [ -z "${DEVENV_WSL:-}" ] && grep -qi microsoft /proc/sys/kernel/osrelease 2>/dev/null; then
    IS_WSL=1
  fi
  if [ -n "${DEVENV_BREW_PREFIX:-}" ]; then
    BREW_PREFIX=$DEVENV_BREW_PREFIX
  elif [ "$OS" = darwin ]; then
    case "$ARCH" in arm64) BREW_PREFIX=/opt/homebrew ;; *) BREW_PREFIX=/usr/local ;; esac
  else
    BREW_PREFIX=/home/linuxbrew/.linuxbrew
  fi
  BREW="$BREW_PREFIX/bin/brew"
  if [ "$OS" = darwin ]; then
    USER_SHELL=zsh RC_FILE="$HOME/.zshrc"
  else
    case "${SHELL:-}" in
      */zsh) USER_SHELL=zsh RC_FILE="$HOME/.zshrc" ;;
      *)     USER_SHELL=bash RC_FILE="$HOME/.bashrc" ;;
    esac
  fi
  PLATFORM_LABEL=$OS
  [ "$IS_WSL" = 1 ] && PLATFORM_LABEL="wsl (${WSL_DISTRO_NAME:-linux})"
  export OS ARCH IS_WSL BREW_PREFIX BREW USER_SHELL RC_FILE PLATFORM_LABEL
}

# Windows home as seen from WSL, e.g. /mnt/c/Users/carso.
windows_home() {
  if [ -n "${DEVENV_WINHOME:-}" ]; then echo "$DEVENV_WINHOME"; return; fi
  local wp
  wp=$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r') || return 1
  [ -n "$wp" ] || return 1
  wslpath -u "$wp"
}
