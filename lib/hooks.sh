# shellcheck shell=bash
# Per-module steps beyond package installs. hook_<module> runs after the
# module's packages are in place. Everything they change is recorded.

hook_rust() {
  local rustup=''
  if [ -x "$BREW_PREFIX/opt/rustup/bin/rustup" ]; then rustup="$BREW_PREFIX/opt/rustup/bin/rustup"
  elif has rustup; then rustup=$(command -v rustup)
  fi
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
