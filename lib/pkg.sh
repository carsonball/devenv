# shellcheck shell=bash
# Package installation. Homebrew is the single package manager on macOS and
# Linux/WSL so every module uses the same package names and recent versions.
# Only packages devenv actually installed are recorded, so undo never removes
# something you already had.

BREW_FORMULAE='' BREW_CASKS='' BREW_READY=0

brew_refresh() {
  [ -x "$BREW" ] || { BREW_FORMULAE='' BREW_CASKS=''; return 0; }
  BREW_FORMULAE=" $("$BREW" list --formula -1 2>/dev/null | tr '\n' ' ') "
  if [ "$OS" = darwin ]; then
    BREW_CASKS=" $("$BREW" list --cask -1 2>/dev/null | tr '\n' ' ') "
  fi
}

# Minimum versions for tools other things depend on (Mason's language servers need node 20+).
too_old() {
  local major
  case "$1" in
    node) major=$(node --version 2>/dev/null | sed 's/^v//; s/\..*//')
          [ -n "$major" ] && [ "$major" -lt 20 ] 2>/dev/null ;;
    *) return 1 ;;
  esac
}

# Formula names without a tap prefix (homebrew/core/foo -> foo).
brew_short() { local n; for n in "$@"; do printf '%s ' "${n##*/}"; done; }

brew_has()      { case "$BREW_FORMULAE" in *" $1 "*) return 0 ;; esac; return 1; }
brew_has_cask() { case "$BREW_CASKS" in *" $1 "*) return 0 ;; esac; return 1; }

ensure_sudo() {
  is_dry && return 0
  [ "$(id -u)" = 0 ] && return 0
  has sudo || die "sudo is required to install system prerequisites"
  if ! sudo -n true 2>/dev/null; then
    log "  devenv needs your password once for system-level installs."
    sudo -v </dev/tty || die "could not get sudo"
  fi
}

apt_prereqs() {
  [ "$OS" = linux ] || return 0
  has dpkg || { warn "not a Debian/Ubuntu system: install curl, git, gcc, make and file yourself"; return 0; }
  local p missing=''
  for p in build-essential procps curl file git unzip; do
    dpkg -s "$p" >/dev/null 2>&1 || missing="$missing $p"
  done
  [ -n "$missing" ] || return 0
  step "system prerequisites:$missing"
  ensure_sudo
  # shellcheck disable=SC2086
  prun "Updating apt" '' sudo apt-get update -qq \
    && prun "Installing system prerequisites" '' sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $missing \
    || die "apt-get failed; see $RUN_LOG"
  for p in $missing; do
    if is_dry || dpkg -s "$p" >/dev/null 2>&1; then record cli apt "$p"; fi
  done
}

ensure_homebrew() {
  [ "$BREW_READY" = 1 ] && return 0
  if [ ! -x "$BREW" ] && has brew; then
    BREW=$(command -v brew)
    BREW_PREFIX=$("$BREW" --prefix)
  fi
  if [ ! -x "$BREW" ]; then
    ! is_dry && [ "$OS" = linux ] && [ "$(id -u)" = 0 ] && die "Homebrew refuses to run as root. Run devenv as your normal user."
    apt_prereqs
    if is_dry; then
      step "would run the official Homebrew installer"
      record cli homebrew "$BREW_PREFIX"
      BREW_READY=1
      return 0
    fi
    ensure_sudo
    local tmp
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/devenv-brew.XXXXXX")
    curl -fsSL -o "$tmp/install.sh" https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh \
      || die "could not download the Homebrew installer"
    step "running the official Homebrew installer (into $BREW_PREFIX)"
    prun "Downloading and installing Homebrew" "probe_size '$BREW_PREFIX'" env NONINTERACTIVE=1 /bin/bash "$tmp/install.sh" \
      || { rm -rf "$tmp"; die "Homebrew install failed; see $RUN_LOG"; }
    rm -rf "$tmp"
    [ -x "$BREW" ] || die "Homebrew installed but $BREW is missing"
    record cli homebrew "$BREW_PREFIX"
  else
    apt_prereqs
  fi
  eval "$("$BREW" shellenv)"
  export HOMEBREW_NO_ENV_HINTS=1 HOMEBREW_NO_INSTALL_CLEANUP=1
  brew_refresh
  BREW_READY=1
}

# brew_install <module> <spec...>
# spec is "formula" or "formula:command"; with a command, an existing install
# of that command from anywhere (nvm, apt, ...) is used instead of brew's.
brew_install() {
  local module=$1 spec name cmd todo='' found; shift
  for spec in "$@"; do
    name=${spec%%:*}; cmd=''
    case "$spec" in *:*) cmd=${spec#*:} ;; esac
    if brew_has "${name##*/}"; then continue; fi
    if [ -n "$cmd" ] && found=$(command -v "$cmd" 2>/dev/null); then
      if too_old "$cmd"; then
        step "your $cmd ($found, $("$cmd" --version 2>/dev/null | head -n 1)) is too old; adding Homebrew's"
      else
        step "using your existing $cmd ($found)"
        continue
      fi
    fi
    todo="$todo $name"
  done
  [ -n "$todo" ] || return 0
  step "with Homebrew:$todo"
  if is_dry; then
    for name in $todo; do step "would brew install $name"; done
    return 0
  fi
  # shellcheck disable=SC2086
  # Several formulae get a bar; a single one just a spinner with brew's latest line.
  local label="Installing packages" probe
  probe="probe_present '$BREW_PREFIX/opt' packages $(brew_short $todo)"
  case "${todo# }" in *" "*) ;; *) label="Installing ${todo# }" probe='' ;; esac
  if ! prun "$label" "$probe" "$BREW" install $todo; then
    # One bad formula fails the whole batch; retry the rest one at a time.
    brew_refresh
    for name in $todo; do
      brew_has "${name##*/}" || prun "Installing $name" '' "$BREW" install "$name" || warn "brew could not install $name; see $RUN_LOG"
    done
  fi
  brew_refresh
  for name in $todo; do
    name=${name##*/}
    if brew_has "$name"; then record "$module" brew "$name"; ok "$name"
    else warn "$name did not install"; FAILURES="$FAILURES brew:$name"
    fi
  done
}

cask_install() {
  local module=$1 name todo=''; shift
  [ "$OS" = darwin ] || return 0
  for name in "$@"; do
    brew_has_cask "$name" && continue
    # Respect apps installed by dragging into /Applications.
    case "$name" in
      wezterm) [ -d /Applications/WezTerm.app ] && { step "using your existing WezTerm.app"; continue; } ;;
    esac
    todo="$todo $name"
  done
  [ -n "$todo" ] || return 0
  step "apps:$todo"
  if is_dry; then
    for name in $todo; do step "would brew install --cask $name"; done
    return 0
  fi
  # shellcheck disable=SC2086
  prun "Installing apps" "probe_present '$BREW_PREFIX/Caskroom' apps $todo" "$BREW" install --cask $todo || warn "brew reported errors; see $RUN_LOG"
  brew_refresh
  for name in $todo; do
    if brew_has_cask "$name"; then record "$module" cask "$name"; ok "$name"
    else warn "$name did not install"; FAILURES="$FAILURES cask:$name"
    fi
  done
}

winget_has() { winget.exe list -e --id "$1" --accept-source-agreements 2>/dev/null | tr -d '\r' | grep -qi -- "$1"; }

# Install a Windows app from inside WSL (WezTerm runs natively on Windows).
winget_install() {
  local module=$1 id=$2
  [ "$IS_WSL" = 1 ] || return 0
  if ! has winget.exe; then
    warn "winget.exe not reachable from WSL; install $id on Windows yourself"
    return 0
  fi
  if winget_has "$id"; then step "using your existing $id on Windows"; return 0; fi
  step "on Windows: $id"
  if is_dry; then step "would winget install $id"; return 0; fi
  prun "Installing $id on Windows" '' winget.exe install -e --id "$id" --silent --accept-source-agreements --accept-package-agreements
  if winget_has "$id"; then record "$module" winget "$id"; ok "$id"
  else warn "$id did not install (see $RUN_LOG)"; FAILURES="$FAILURES winget:$id"
  fi
}
