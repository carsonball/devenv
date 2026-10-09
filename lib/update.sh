# shellcheck shell=bash
# `devenv outdated` and `devenv update`: newer versions of what devenv installed.
# Only packages in the manifest count, so anything you already had stays yours.
# Upgrades are not recorded: undo removes a package, it never downgrades one.
#
# Each source prints one tab-separated line per outdated package:
#   <source>  <name>  <installed>  <latest>
# sources: brew, cask, winget, rust, plugin (lazy.nvim), tool (Mason)

# Targets of <kind> records for the given modules (every module when none).
recorded() { # recorded <kind> [modules]
  local m
  if [ -z "$2" ]; then records_where 5 "$1" | cut -f6; return 0; fi
  for m in $2; do records_where 4 "$m" | awk -F'\t' -v k="$1" '$5 == k { print $6 }'; done
}

# `brew outdated --verbose` lines: "go (1.22.1) < 1.22.2", "wezterm (1) != 2".
outdated_brew() { # outdated_brew <formula|cask> <names...>
  local kind=$1 src=brew; shift
  [ "$kind" = cask ] && src=cask
  [ $# -gt 0 ] || return 0
  "$BREW" outdated "--$kind" --verbose "$@" 2>/dev/null | awk -v s="$src" '{
    r = $0; sub(/^[^(]*\(/, "", r); from = r; sub(/\).*/, "", from)
    to = r; sub(/^[^)]*\) (<|!=) /, "", to); sub(/ .*/, "", to)
    print s "\t" $1 "\t" from "\t" to }'
}

outdated_winget() { # outdated_winget <ids...>
  local id
  [ "$IS_WSL" = 1 ] && has winget.exe || return 0
  for id in "$@"; do
    winget.exe list --upgrade-available -e --id "$id" --accept-source-agreements 2>/dev/null | tr -d '\r' \
      | awk -v id="$id" '{ for (i = 1; i < NF - 1; i++) if ($i == id) { print "winget\t" id "\t" $(i + 1) "\t" $(i + 2); exit } }'
  done
}

# Only when devenv set up the toolchain; `rustup check` lines look like
# "stable-x86_64-apple-darwin - Update available : 1.80.0 (abc 2024-07-21) -> 1.81.0 (def 2024-09-04)".
outdated_rust() {
  local rustup
  [ -n "$(find_record dir "${RUSTUP_HOME:-$HOME/.rustup}")" ] || return 0
  rustup=$(rustup_bin) || return 0
  "$rustup" check 2>/dev/null | awk -F' : ' '/Update available/ && $1 !~ /^rustup / {
    split($1, n, " "); split($2, v, " -> "); split(v[1], f, " "); split(v[2], t, " ")
    print "rust\t" n[1] "\t" f[1] "\t" t[1] }'
}

# nvim_versions <check|update>: run nvim_update.lua; outdated lines on stdout.
nvim_versions() {
  local nvim out rc
  nvim=$(nvim_bin) || return 0
  out=$(scratch)
  DEVENV_NVIM_MODE=$1 "$nvim" --headless -c "luafile $DEVENV_HOME/lib/nvim_update.lua" >"$out" 2>&1
  rc=$?
  [ -n "${RUN_LOG:-}" ] && cat "$out" >>"$RUN_LOG"
  awk '$1 == "[devenv]" && $2 == "outdated" { print $3 "\t" $4 "\t" $5 "\t" $6 }' "$out"
  grep '^\[devenv\]' "$out" | grep -v '^\[devenv\] outdated ' | sed 's/^\[devenv\] //' | while IFS= read -r l; do warn "Neovim: $l"; done
  rm -f "$out"
  return "$rc"
}

# Every outdated package for the given modules, in the format above.
outdated_all() { # outdated_all [modules]
  local mods=$1 f
  # shellcheck disable=SC2046
  outdated_brew formula $(for f in $(recorded brew "$mods"); do brew_has "$f" && echo "$f"; done)
  # shellcheck disable=SC2046
  [ "$OS" = darwin ] && outdated_brew cask $(for f in $(recorded cask "$mods"); do brew_has_cask "$f" && echo "$f"; done)
  # shellcheck disable=SC2046
  outdated_winget $(recorded winget "$mods")
  if [ -z "$mods" ] || word_in rust "$mods"; then outdated_rust; fi
  if { [ -z "$mods" ] || word_in nvim "$mods"; } && [ "${NO_SYNC:-0}" != 1 ]; then
    nvim_versions check || warn "could not check Neovim plugins and tools"
  fi
  return 0
}

# Names of one source's outdated packages in a list file.
outdated_names() { awk -F'\t' -v s="$1" '$1 == s { print $2 }' "$2" | tr '\n' ' '; }

source_label() {
  case "$1" in
    brew) echo "Homebrew" ;; cask) echo "Homebrew apps" ;; winget) echo "Windows apps" ;;
    rust) echo "Rust toolchain" ;; plugin) echo "Neovim plugins" ;; tool) echo "Mason tools" ;; *) echo "$1" ;;
  esac
}

show_outdated() { # show_outdated <file>
  local src prev='' name from to
  while IFS="$TAB" read -r src name from to; do
    [ "$src" = "$prev" ] || log "  $(source_label "$src")"
    prev=$src
    log "    $(printf '%-28s' "$name") $from -> $to"
  done <"$1"
}

# Modules named on the command line (all active modules when none).
update_modules() {
  local w m mods=''
  for w in "$@"; do
    m=$(resolve_word "$w") || die "unknown module '$w'"
    word_in "$m" "$(active_modules)" || die "$m is not installed"
    mods="$mods $m"
  done
  echo "$mods"
}

ensure_brew_env() {
  BREW_READY=1
  [ -x "$BREW" ] && eval "$("$BREW" shellenv)" && brew_refresh
  return 0
}

cmd_outdated() {
  local mods list n
  mods=$(update_modules "$@") || exit $?
  ensure_brew_env
  info "Checking for newer versions of what devenv installed..."
  list=$(scratch)
  outdated_all "$mods" >"$list"
  n=$(grep -c . "$list")
  if [ "$n" = 0 ]; then info "Everything is up to date."
  else
    show_outdated "$list"
    log ""
    log "  $n out of date. Install them with \`devenv update${mods}\`."
  fi
  rm -f "$list"
}

cmd_update() {
  local mods list n names
  mods=$(update_modules "$@") || exit $?
  ensure_brew_env
  info "devenv on $PLATFORM_LABEL: checking for newer versions..."
  list=$(scratch)
  outdated_all "$mods" >"$list"
  n=$(grep -c . "$list")
  if [ "$n" = 0 ]; then rm -f "$list"; info "Everything is up to date."; return 0; fi
  log "  Will update:"
  show_outdated "$list"
  log "  Updates can't be undone; \`devenv undo\` still removes the packages."
  if ! is_dry && ! confirm "Proceed?"; then rm -f "$list"; log "Nothing changed."; exit 1; fi

  RUN_ID="update-$(new_run_id)"; export RUN_ID
  FAILURES=''
  if ! is_dry; then
    state_init
    RUN_LOG="$STATE_DIR/runs/$RUN_ID.log"; export RUN_LOG; : >"$RUN_LOG"
    history_add "update:$mods"
  fi
  names=$(outdated_names brew "$list")
  # shellcheck disable=SC2086
  [ -n "$names" ] && { prun "Updating $names" '' "$BREW" upgrade --formula $names || FAILURES="$FAILURES brew"; }
  names=$(outdated_names cask "$list")
  # shellcheck disable=SC2086
  [ -n "$names" ] && { prun "Updating $names" '' "$BREW" upgrade --cask $names || FAILURES="$FAILURES cask"; }
  for names in $(outdated_names winget "$list"); do
    prun "Updating $names on Windows" '' winget.exe upgrade -e --id "$names" --silent --accept-source-agreements --accept-package-agreements \
      || FAILURES="$FAILURES winget:$names"
  done
  [ -n "$(outdated_names rust "$list")" ] && { prun "Updating the Rust toolchain" '' "$(rustup_bin)" update --no-self-update || FAILURES="$FAILURES rust"; }
  if [ -n "$(outdated_names plugin "$list")$(outdated_names tool "$list")" ]; then
    prun "Updating Neovim plugins and tools" '' env DEVENV_NVIM_MODE=update "$(nvim_bin)" --headless -c "luafile $DEVENV_HOME/lib/nvim_update.lua" \
      || FAILURES="$FAILURES neovim"
  fi
  rm -f "$list"

  log ""
  if is_dry; then info "Dry run: nothing was changed."; return 0; fi
  if [ -n "$FAILURES" ]; then warn "did not complete:$FAILURES (details in $RUN_LOG)"; return 1; fi
  info "Updated $n packages."
}
