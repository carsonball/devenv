# shellcheck shell=bash
# Module definitions live in modules/<name>.conf as plain key=value lines (no
# code is executed). Keys:
#   desc       one-line description
#   core=1     always installed (unless you undo it)
#   aliases    other names, extensions or tools that select this module
#   requires   modules this one builds on
#   brew       Homebrew formulae ("formula" or "formula:command", see pkg.sh)
#   brew_darwin / brew_linux   platform-only formulae
#   cask       macOS apps
#   winget     Windows apps (installed from WSL)
#   extras     LazyVim extras to enable
#   notes / notes_darwin / notes_linux / notes_wsl   shown after install
# Optional companions: templates/nvim/modules/<name>.lua (Neovim specs),
# templates/shell/<name>.sh (shell snippet), hook_<name> in hooks.sh.

CORE_ORDER='cli shellrc tmux nvim wezterm'

mod_file()   { printf '%s/modules/%s.conf\n' "$DEVENV_HOME" "$1"; }
mod_exists() { [ -f "$(mod_file "$1")" ]; }
mod_get()    { sed -n "s/^$2=//p" "$(mod_file "$1")" | head -n 1; }
mod_is_core() { [ "$(mod_get "$1" core)" = 1 ]; }

# Value of <key> plus its platform-specific variants.
mod_get_plat() {
  local v
  v="$(mod_get "$1" "$2") $(mod_get "$1" "${2}_$OS")"
  [ "$IS_WSL" = 1 ] && v="$v $(mod_get "$1" "${2}_wsl")"
  echo $v
}

all_modules() {
  local f
  for f in "$DEVENV_HOME"/modules/*.conf; do basename "$f" .conf; done
}

lang_modules() {
  local m
  for m in $(all_modules); do mod_is_core "$m" || echo "$m"; done
}

# Map a user word (go, ts, .tsx, kubernetes, Dockerfile) to a module name.
resolve_word() {
  local w m
  w=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  w=${w#\*}
  mod_exists "$w" && { echo "$w"; return 0; }
  for m in $(all_modules); do
    if word_in "$w" "$(mod_get "$m" aliases)"; then echo "$m"; return 0; fi
  done
  return 1
}

# Add requirements (depth first) and put modules in install order:
# core modules first in CORE_ORDER, then the rest as given.
order_modules() {
  local want='' m r out='' changed=1
  want=" $* "
  while [ "$changed" = 1 ]; do
    changed=0
    for m in $want; do
      for r in $(mod_get "$m" requires); do
        case "$want" in *" $r "*) ;; *) want="$want$r "; changed=1 ;; esac
      done
    done
  done
  for m in $CORE_ORDER; do case "$want" in *" $m "*) out="$out $m" ;; esac; done
  for m in $want; do word_in "$m" "$CORE_ORDER" || out="$out $m"; done
  echo $out
}
