# shellcheck shell=bash
# Per-module steps beyond package installs. hook_<module> runs after the
# module's packages are in place. Everything they change is recorded.

rustup_bin() {
  if [ -x "$BREW_PREFIX/opt/rustup/bin/rustup" ]; then echo "$BREW_PREFIX/opt/rustup/bin/rustup"
  else command -v rustup
  fi
}

hook_rust() {
  local rustup
  rustup=$(rustup_bin)
  if [ -z "$rustup" ]; then
    is_dry && step "would run: rustup default stable + rust-analyzer, clippy, rustfmt"
    return 0
  fi
  if "$rustup" toolchain list 2>/dev/null | grep -q stable; then return 0; fi
  step "Rust stable toolchain"
  track_new_dir rust "${RUSTUP_HOME:-$HOME/.rustup}"
  track_new_dir rust "${CARGO_HOME:-$HOME/.cargo}"
  prun "Installing the Rust toolchain" '' "$rustup" default stable || { warn "rustup default stable failed"; FAILURES="$FAILURES rustup"; return 0; }
  prun "Adding rust-analyzer, clippy, rustfmt" '' "$rustup" component add rust-analyzer clippy rustfmt || warn "could not add rust components"
}

hook_docker() {
  # Homebrew's compose and buildx are CLI plugins; docker finds them here.
  local p
  for p in docker-compose docker-buildx; do
    if brew_has "$p" || is_dry; then
      link_file docker "$BREW_PREFIX/opt/$p/bin/$p" "$HOME/.docker/cli-plugins/$p"
    fi
  done
}

# Claude Code: Anthropic's native installer, the same on macOS, Linux and WSL
# (the Homebrew cask is macOS-only). It puts the CLI in ~/.local/share/claude
# with a ~/.local/bin/claude link and updates itself there; undo removes both.
# ~/.claude and ~/.claude.json (login, settings, history) are never recorded.
hook_claude() {
  local link="$HOME/.local/bin/claude" tmp target
  if has claude || [ -e "$link" ]; then step "using your existing claude ($(command -v claude || echo "$link"))"; return 0; fi
  step "Claude Code (Anthropic's installer)"
  if is_dry; then step "would run https://claude.ai/install.sh"; return 0; fi
  track_new_dir claude "$HOME/.local/share/claude"
  track_new_dir claude "${XDG_STATE_HOME:-$HOME/.local/state}/claude"
  track_new_dir claude "${XDG_CACHE_HOME:-$HOME/.cache}/claude"
  ensure_dir claude "$HOME/.local/bin"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/devenv-claude.XXXXXX")
  if run curl -fsSL -o "$tmp/install.sh" https://claude.ai/install.sh \
    && prun "Installing Claude Code" "probe_size '$HOME/.local/share/claude'" bash "$tmp/install.sh" \
    && { [ -L "$link" ] || [ -x "$link" ]; }; then
    if [ -L "$link" ]; then target=$(readlink "$link"); record claude link "$link" "$target"
    else record claude file "$link" '' "$(sha_of "$link")"
    fi
    ok "Claude Code"
  else
    warn "could not install Claude Code (see $RUN_LOG)"; FAILURES="$FAILURES claude"
  fi
  rm -rf "$tmp"
}

# Desktop Linux has no font cask: fetch the Nerd Font release into ~/.local/share/fonts.
# (macOS gets it as a Homebrew cask, Windows through winget; see modules/wezterm.conf.)
hook_wezterm() {
  [ "$OS" = linux ] && [ "$IS_WSL" != 1 ] || return 0
  local dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMonoNerdFont" tmp
  [ -d "$dir" ] && return 0
  if fc-list 2>/dev/null | grep -q "JetBrainsMono Nerd Font"; then step "using your installed JetBrainsMono Nerd Font"; return 0; fi
  step "JetBrainsMono Nerd Font"
  if is_dry; then step "would download JetBrainsMono Nerd Font into $(tilde "$dir")"; return 0; fi
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/devenv-font.XXXXXX")
  if prun "Downloading JetBrainsMono Nerd Font" "probe_size '$tmp'" curl -fsSL -o "$tmp/font.zip" https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip \
    && ensure_dir wezterm "$(dirname "$dir")" && record wezterm dir "$dir" && mkdir -p "$dir" \
    && run unzip -qo "$tmp/font.zip" '*.ttf' -d "$dir"; then
    has fc-cache && run fc-cache -f "$dir"
    ok "JetBrainsMono Nerd Font"
  else
    warn "could not install JetBrainsMono Nerd Font"; FAILURES="$FAILURES font"
  fi
  rm -rf "$tmp"
}

# --- Claude Code add-ons ------------------------------------------------------
# Plugins and skills go into ~/.claude through Claude Code's own commands, and
# undo takes them out the same way. Your login, settings and history stay put.

claude_bin() {
  if has claude; then command -v claude
  elif [ -x "$HOME/.local/bin/claude" ]; then echo "$HOME/.local/bin/claude"
  fi
}

# claude_plugin <module> <plugin@marketplace> <github owner/repo>
claude_plugin() {
  local module=$1 plugin=$2 repo=$3 market=${2#*@} cl
  cl=$(claude_bin)
  if [ -z "$cl" ]; then
    is_dry && { step "would add the $plugin Claude Code plugin from $repo"; return 0; }
    warn "claude not found; skipped the $plugin plugin"; FAILURES="$FAILURES $module"; return 0
  fi
  if [ -n "$(find_record plugin "$plugin")" ]; then return 0; fi
  if "$cl" plugin list 2>/dev/null | grep -qw "${plugin%@*}"; then step "using your existing $plugin plugin"; return 0; fi
  if is_dry; then step "would add the $plugin Claude Code plugin from $repo"; return 0; fi
  if ! "$cl" plugin marketplace list 2>/dev/null | grep -qw "$market"; then
    run "$cl" plugin marketplace add "$repo" || { warn "could not add the $market marketplace ($repo)"; FAILURES="$FAILURES $module"; return 0; }
    record "$module" marketplace "$market" "$repo"
  fi
  if run "$cl" plugin install "$plugin"; then
    record "$module" plugin "$plugin"
    ok "Claude Code plugin $plugin"
  else
    warn "could not install the $plugin plugin"; FAILURES="$FAILURES $module"
  fi
}

hook_caveman()  { claude_plugin caveman caveman@caveman JuliusBrussee/caveman; }
hook_ponytail() { claude_plugin ponytail ponytail@ponytail DietrichGebert/ponytail; }

# Lavish's skill is a stub that runs `npx -y lavish-axi`, so the CLI itself is
# fetched on demand (node comes with the cli module). A copy of the skill ships
# in templates/claude/skills/lavish; an existing one of yours is left alone.
hook_lavish() {
  local dir="$HOME/.claude/skills/lavish"
  if { [ -e "$dir" ] || [ -L "$dir" ]; } && [ -z "$(find_record file "$dir/SKILL.md")" ]; then
    step "using your existing lavish skill ($(tilde "$dir"))"; return 0
  fi
  install_file lavish "$DEVENV_HOME/templates/claude/skills/lavish/SKILL.md" "$dir/SKILL.md"
}

# no-mistakes: the project's own installer puts the binary in ~/.no-mistakes/bin,
# links it into ~/.local/bin and starts its daemon (launchd on macOS, a systemd
# user service on Linux). Telemetry is off (see templates/shell/nomistakes.sh).
hook_nomistakes() {
  local home="$HOME/.no-mistakes" link="$HOME/.local/bin/no-mistakes" tmp
  if has no-mistakes || [ -e "$link" ]; then step "using your existing no-mistakes ($(command -v no-mistakes || echo "$link"))"; return 0; fi
  step "no-mistakes (the project's installer)"
  if is_dry; then step "would run https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh"; return 0; fi
  track_new_dir nomistakes "$home"
  ensure_dir nomistakes "$HOME/.local/bin"
  [ "$OS" = linux ] && ensure_dir nomistakes "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
  tmp=$(mktemp -d "${TMPDIR:-/tmp}/devenv-nm.XXXXXX")
  if run curl -fsSL -o "$tmp/install.sh" https://raw.githubusercontent.com/kunchenguid/no-mistakes/main/docs/install.sh \
    && prun "Installing no-mistakes" "probe_size '$home'" env NO_MISTAKES_INSTALL_DIR="$home/bin" NO_MISTAKES_LINK_DIR="$HOME/.local/bin" NO_MISTAKES_TELEMETRY=0 sh "$tmp/install.sh" \
    && [ -x "$home/bin/no-mistakes" ]; then
    [ -L "$link" ] && record nomistakes link "$link" "$(readlink "$link")"
    # The installer starts the daemon; recorded last so undo stops it first.
    record nomistakes daemon no-mistakes
    ok "no-mistakes"
  else
    warn "could not install no-mistakes (see $RUN_LOG)"; FAILURES="$FAILURES nomistakes"
  fi
  rm -rf "$tmp"
}

nm_units() { ls "${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"/no-mistakes-daemon-*.service 2>/dev/null; }

# daemon_remove <name>: stop and remove a background service a hook set up.
daemon_remove() {
  case "$1" in
    no-mistakes)
      local bin="$HOME/.no-mistakes/bin/no-mistakes" u
      if [ -x "$bin" ]; then
        [ "$OS" = darwin ] && { run "$bin" daemon uninstall || return 1; }
        run "$bin" daemon stop || true
      fi
      for u in $(nm_units); do
        has systemctl && run systemctl --user disable --now "$(basename "$u")"
        rm -f "$u"
      done
      has systemctl && [ "$OS" = linux ] && run systemctl --user daemon-reload
      return 0 ;;
    *) warn "don't know how to remove the $1 service"; return 1 ;;
  esac
}
