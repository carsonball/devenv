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
  info "Installing the stable Rust toolchain"
  track_new_dir rust "${RUSTUP_HOME:-$HOME/.rustup}"
  track_new_dir rust "${CARGO_HOME:-$HOME/.cargo}"
  run "$rustup" default stable || { warn "rustup default stable failed"; FAILURES="$FAILURES rustup"; return 0; }
  run "$rustup" component add rust-analyzer clippy rustfmt || warn "could not add rust components"
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
