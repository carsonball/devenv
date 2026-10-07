#!/bin/bash
# Bootstrap devenv on a fresh machine, then run `devenv install` with your args.
#
#   curl -fsSL https://raw.githubusercontent.com/carsonball/devenv/main/install.sh | bash -s -- go docker k8s ts
#
# Needs only bash, curl and tar, which macOS and Ubuntu ship with. devenv itself
# goes to ~/.local/share/devenv and is linked as ~/.local/bin/devenv; it is not
# part of the undo manifest (remove it with: rm -rf ~/.local/share/devenv ~/.local/bin/devenv).
#
# Env: DEVENV_REPO (owner/name on GitHub), DEVENV_REF (branch or tag), DEVENV_DIR.

# Everything is inside main(), called on the last line, so a download cut off
# midway through `curl | bash` runs nothing instead of a partial script.
main() {
  DEVENV_REPO=${DEVENV_REPO:-carsonball/devenv}
  DEVENV_REF=${DEVENV_REF:-main}
  DEST=${DEVENV_DIR:-$HOME/.local/share/devenv}
  BIN="$HOME/.local/bin"

  say() { printf '==> %s\n' "$*" >&2; }
  die() { printf 'error: %s\n' "$*" >&2; exit 1; }

  update_only=0
  if [ "${1:-}" = --update ]; then update_only=1; shift; fi

  # Running from a checkout (git clone, unpacked folder, or a WSL path to one)?
  here=''
  case "${BASH_SOURCE[0]:-}" in
    */install.sh|install.sh) here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd) ;;
  esac

  if [ -n "$here" ] && [ -x "$here/bin/devenv" ] && [ "$update_only" = 0 ]; then
    src=$here
    say "Using devenv from $src"
  else
    case "$DEVENV_REPO" in OWNER/*) die "set DEVENV_REPO=<github-user>/<repo> (where you pushed devenv)" ;; esac
    say "Downloading devenv ($DEVENV_REPO@$DEVENV_REF)"
    tmp=$(mktemp -d "${TMPDIR:-/tmp}/devenv-install.XXXXXX") || die "mktemp failed"
    curl -fsSL "https://github.com/$DEVENV_REPO/archive/$DEVENV_REF.tar.gz" -o "$tmp/devenv.tgz" \
      || die "could not download https://github.com/$DEVENV_REPO (is the repo public?)"
    mkdir "$tmp/x" && tar -xzf "$tmp/devenv.tgz" -C "$tmp/x" || die "could not unpack the download"
    unpacked=$(find "$tmp/x" -mindepth 1 -maxdepth 1 -type d | head -n 1)
    [ -x "$unpacked/bin/devenv" ] || die "download does not look like devenv"
    mkdir -p "$(dirname "$DEST")"
    rm -rf "$DEST.old"
    if [ -e "$DEST" ]; then mv "$DEST" "$DEST.old" || die "could not move the old $DEST aside"; fi
    mv "$unpacked" "$DEST" || die "could not install to $DEST"
    rm -rf "$DEST.old" "$tmp"
    echo "$DEVENV_REPO" >"$DEST/.source"
    src=$DEST
  fi

  mkdir -p "$BIN"
  ln -sf "$src/bin/devenv" "$BIN/devenv"
  say "devenv is at $BIN/devenv"
  [ "$update_only" = 1 ] && exit 0

  case ":$PATH:" in *":$BIN:"*) ;; *) export PATH="$BIN:$PATH" ;; esac
  exec "$src/bin/devenv" install "$@"
}

main "$@"
