# shellcheck shell=bash
# Reversing manifest records, newest first.

safe_path() {
  case "$1" in
    ''|/|"$HOME"|"$HOME/") return 1 ;;
  esac
  return 0
}

# undo_record <manifest line>. Returns non-zero (and keeps the record) when the
# change could not be reversed, so a later `devenv undo` can retry it.
undo_record() {
  local line=$1 seq module kind target data sha cur b
  seq=$(field "$line" 1); module=$(field "$line" 4); kind=$(field "$line" 5)
  target=$(field "$line" 6); data=$(field "$line" 7); sha=$(field "$line" 8)
  if is_dry; then step "would undo #$seq $kind $target"; return 0; fi
  case "$kind" in
    brew)
      run "$BREW" uninstall "$target" || { warn "could not uninstall $target (another formula may depend on it); kept in the manifest"; return 1; } ;;
    cask)
      run "$BREW" uninstall --cask "$target" || { warn "could not uninstall $target"; return 1; } ;;
    apt)
      # apt-get remove -y also removes anything that depends on the package
      # (things you installed after devenv). Only remove it if nothing else goes.
      local others
      others=$(apt-get -s remove "$target" 2>/dev/null | awk '$1 == "Remv" { print $2 }' | grep -vx -- "$target")
      if [ -n "$others" ]; then
        warn "kept $target: removing it would also remove $(echo $others)"
        return 1
      fi
      ensure_sudo
      run sudo apt-get remove -y -qq "$target" || { warn "could not remove $target"; return 1; } ;;
    winget)
      run winget.exe uninstall -e --id "$target" --silent || { warn "could not uninstall $target on Windows"; return 1; } ;;
    homebrew)
      if [ "${INCLUDE_HOMEBREW:-0}" != 1 ]; then
        warn "kept Homebrew itself (pass --include-homebrew to remove it and everything installed with it)"
        return 1
      fi
      local script
      script=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh) || { warn "could not download the Homebrew uninstaller"; return 1; }
      step "running the official Homebrew uninstaller"
      NONINTERACTIVE=1 /bin/bash -c "$script" || { warn "Homebrew uninstall failed"; return 1; } ;;
    file)
      if [ -e "$target" ] || [ -L "$target" ]; then
        cur=$(sha_of "$target")
        if [ -n "$sha" ] && [ "$cur" != "$sha" ]; then
          b=$(stash "$target")
          warn "you had edited $target; your version is saved at $b"
        else
          rm -f "$target"
        fi
      fi ;;
    replace)
      if [ -e "$target" ] || [ -L "$target" ]; then
        cur=$(sha_of "$target")
        if [ -d "$target" ] || { [ -n "$sha" ] && [ "$cur" = "$sha" ]; }; then
          safe_path "$target" && rm -rf "$target"
        else
          b=$(stash "$target")
          warn "you had edited $target; your version is saved at $b"
        fi
      fi
      if [ -e "$data" ] || [ -L "$data" ]; then
        mkdir -p "$(dirname "$target")"
        mv "$data" "$target"
      else
        warn "original of $target is missing from $data; nothing to restore"
      fi ;;
    dir)
      safe_path "$target" || { warn "refusing to delete $target"; return 1; }
      rm -rf "$target" ;;
    mkdir)
      rmdir "$target" 2>/dev/null || true ;;
    link)
      [ -L "$target" ] && rm -f "$target" ;;
    block)
      if [ -f "$target" ]; then
        local tmp
        tmp=$(mktemp)
        strip_block "$target" >"$tmp"
        if [ "$data" = nl ]; then
          awk 'NR > 1 { print prev } { prev = $0 } END { if (NR) printf "%s", prev }' "$tmp" >"$target"
        else
          cat "$tmp" >"$target"
        fi
        rm -f "$tmp"
        if [ "$data" = created ] && ! grep -q '[^[:space:]]' "$target"; then rm -f "$target"; fi
      fi ;;
    *)
      warn "unknown record kind '$kind' (#$seq)"; return 1 ;;
  esac
  record_delete "$seq"
  history_add "undo #$seq [$module] $kind $target"
  ok "undid #$seq $kind $(tilde "$target")"
  return 0
}

# undo_lines <file with manifest lines> <modules that stay installed>
undo_lines() {
  local file=$1 keep=$2 line kind target module m owner failed=0
  while IFS= read -r line <&3; do
    [ -n "$line" ] || continue
    kind=$(field "$line" 5); target=$(field "$line" 6); module=$(field "$line" 4)
    # A package another remaining module needs is handed over, not removed.
    if [ "$kind" = brew ] || [ "$kind" = cask ] || [ "$kind" = winget ]; then
      owner=''
      for m in $keep; do
        [ "$m" = "$module" ] && continue
        case " $(mod_get_plat "$m" brew) $(mod_get_plat "$m" cask) $(mod_get_plat "$m" winget) " in
          *" $target "*|*" $target:"*|*"/$target "*|*"/$target:"*) owner=$m; break ;;
        esac
      done
      if [ -n "$owner" ]; then
        if is_dry; then step "would keep $target (still needed by $owner)"; continue; fi
        record_set "$(field "$line" 1)" 4 "$owner"
        history_add "keep $target: now owned by $owner"
        step "kept $target (still needed by $owner)"
        continue
      fi
    fi
    undo_record "$line" || failed=1
  done 3<"$file"
  return $failed
}
