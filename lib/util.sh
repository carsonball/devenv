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
  # On a terminal the command line only goes to the log, to keep the screen calm.
  if [ "$UI_TTY" = 1 ] && [ -n "${RUN_LOG:-}" ]; then printf '  - $ %s\n' "$*" >>"$RUN_LOG"
  else step "${C_DIM}\$ $*${C_RESET}"
  fi
  if [ -n "${RUN_LOG:-}" ]; then
    "$@" >>"$RUN_LOG" 2>&1
  else
    "$@"
  fi
}

# --- progress display -------------------------------------------------------
# On a terminal, long steps show one live line (spinner, bar or activity note,
# elapsed time) while their output goes to the run log. Anywhere else (pipes,
# CI, DEVENV_PLAIN=1) they print the same plain lines as `run`.

UI_TTY=0
if [ -t 2 ] && [ "${TERM:-dumb}" != dumb ] && [ -z "${DEVENV_PLAIN:-}" ]; then UI_TTY=1; fi
PHASE=0 PHASES=0 PRUN_PID=''

# phase <title>: a numbered section header, e.g. "==> [2/5] Installing packages".
phase() {
  if [ "$PHASES" -gt 0 ]; then
    PHASE=$((PHASE + 1))
    info "${C_DIM}[$PHASE/$PHASES]${C_RESET}${C_BOLD} $*"
  else
    info "$*"
  fi
}

# Probes print what a progress line shows next to the spinner. A line of the
# form "<done> <total> <unit>" becomes a bar (total 0: just "<done> <unit>");
# anything else is shown as text.
probe_size() { # probe_size <dir>: how much has landed there so far
  du -sk "$1" 2>/dev/null | awk '{ k = $1; if (k > 1048576) printf "%.1f GB so far\n", k / 1048576; else printf "%d MB so far\n", k / 1024 }'
}
probe_present() { # probe_present <dir> <unit> <name...>: how many <dir>/<name> exist
  local dir=$1 unit=$2 n=0 total=0 x; shift 2
  for x in "$@"; do total=$((total + 1)); [ -e "$dir/$x" ] && n=$((n + 1)); done
  echo "$n $total $unit"
}
probe_entries() { # probe_entries <dir> <unit>: how many entries <dir> has
  local n=0 x
  for x in "$1"/*; do [ -e "$x" ] && n=$((n + 1)); done
  echo "$n 0 $2"
}
probe_log() { # the newest "[devenv] progress <done> <total> <unit>" line, else the last log line
  local p
  p=$(tail -c 20000 "$RUN_LOG" 2>/dev/null | tr '\r' '\n' | sed -n 's/^\[devenv\] progress //p' | tail -n 1)
  if [ -n "$p" ]; then echo "$p"; else probe_last; fi
}
probe_last() { # the last non-empty line of output
  tail -c 4000 "$RUN_LOG" 2>/dev/null | tr '\r' '\n' | grep -v -e '^[[:space:]]*$' -e '^  - \$ ' | tail -n 1
}

fmt_secs() { if [ "$1" -ge 60 ]; then printf '%dm%02ds' $(($1 / 60)) $(($1 % 60)); else printf '%ds' "$1"; fi; }

progress_line() { # progress_line <label> <secs> <note> <tick> <cols>
  local label=$1 secs=$2 note=$3 tick=$4 cols=$5 spin d t u bar='' w=24 f i room
  case $((tick % 10)) in
    0) spin='⠋' ;; 1) spin='⠙' ;; 2) spin='⠹' ;; 3) spin='⠸' ;; 4) spin='⠼' ;;
    5) spin='⠴' ;; 6) spin='⠦' ;; 7) spin='⠧' ;; 8) spin='⠇' ;; *) spin='⠏' ;;
  esac
  # Keep only printable ASCII from command output so width math stays right.
  note=$(printf '%s' "$note" | LC_ALL=C tr -cd ' -~' | sed 's/^ *//')
  # shellcheck disable=SC2086
  set -f; set -- $note; set +f
  if [ $# -ge 3 ] && [ "$1" -ge 0 ] 2>/dev/null && [ "$2" -ge 0 ] 2>/dev/null; then
    d=$1 t=$2; shift 2; u=$*
    if [ "$t" -gt 0 ]; then
      [ "$d" -gt "$t" ] && d=$t
      f=$((d * w / t)); i=0
      while [ $i -lt $w ]; do if [ $i -lt $f ]; then bar="$bar█"; else bar="$bar░"; fi; i=$((i + 1)); done
      note="$bar $d/$t $u"
    else
      note="$d $u"
    fi
  else
    room=$((cols - ${#label} - 20))
    [ "$room" -lt 10 ] && note=''
    [ "${#note}" -gt "$room" ] 2>/dev/null && note="${note:0:$((room - 3))}..."
  fi
  printf '\r\033[K  %s%s%s %s  %s  %s%s%s' "$C_BLUE" "$spin" "$C_RESET" "$label" "$note" "$C_DIM" "$(fmt_secs "$secs")" "$C_RESET" >&2
}

progress_abort() {
  [ -n "$PRUN_PID" ] && kill "$PRUN_PID" 2>/dev/null
  printf '\r\033[K\033[?25h' >&2
  err "interrupted; what finished so far is recorded (see \`devenv status\`)"
  exit 130
}

# prun <label> <probe> <command...>: run a long command like `run` does, with a
# live progress line on a terminal. <probe> is a probe_* call (or '' for the
# last line of output).
prun() {
  local label=$1 probe=${2:-probe_last} pid start=$SECONDS tick=0 note='' rc cols; shift 2
  if is_dry || [ "$UI_TTY" != 1 ] || [ -z "${RUN_LOG:-}" ]; then run "$@"; return; fi
  printf '  - $ %s\n' "$*" >>"$RUN_LOG"
  cols=$(tput cols 2>/dev/null || echo 80)
  "$@" </dev/null >>"$RUN_LOG" 2>&1 &
  pid=$!; PRUN_PID=$pid
  trap progress_abort INT TERM
  printf '\033[?25l' >&2
  while kill -0 "$pid" 2>/dev/null; do
    if [ $((tick % 5)) = 0 ]; then note=$(eval "$probe" 2>/dev/null | head -n 1); fi
    progress_line "$label" $((SECONDS - start)) "$note" "$tick" "$cols"
    tick=$((tick + 1))
    sleep 0.2
  done
  wait "$pid"; rc=$?
  PRUN_PID=''
  trap - INT TERM
  printf '\r\033[K\033[?25h' >&2
  [ "$rc" = 0 ] || step "${C_DIM}$label failed after $(fmt_secs $((SECONDS - start)))${C_RESET}"
  return "$rc"
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
