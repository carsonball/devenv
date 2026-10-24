# shellcheck shell=bash
# Tracked file-system changes. Every function here records what it did in the
# manifest so `devenv undo` can reverse it exactly.

backup_path() {
  case "$1" in
    "$HOME"/*) printf '%s/backups/%s/home%s\n' "$STATE_DIR" "${RUN_ID:-manual}" "${1#"$HOME"}" ;;
    *)         printf '%s/backups/%s%s\n' "$STATE_DIR" "${RUN_ID:-manual}" "$1" ;;
  esac
}

# Move whatever sits at <path> into the backup area; STASHED says where it went.
# Called directly, not in $(...), so a --step answer of q reaches the whole run.
stash() {
  local path=$1
  STASHED=$(backup_path "$path")
  if [ -e "$STASHED" ] || [ -L "$STASHED" ]; then STASHED="$STASHED.$$.$(date +%s)"; fi
  mkdir -p "$(dirname "$STASHED")"
  mv "$path" "$STASHED"
}

# ensure_dir <module> <dir>: create missing ancestors, recording each one.
# Undo removes them only if they are empty by then.
ensure_dir() {
  local module=$1 dir=$2 missing='' d
  d=$dir
  while [ ! -d "$d" ] && [ "$d" != / ] && [ "$d" != . ]; do
    missing="$d $missing"
    d=$(dirname "$d")
  done
  [ -n "$missing" ] || return 0
  if is_dry; then return 0; fi
  for d in $missing; do
    mkdir "$d" || return 1
    record "$module" mkdir "$d"
  done
}

# adopt_dir <module> <dir>: devenv takes over <dir> entirely. An existing,
# untracked directory is moved to the backup area first.
adopt_dir() {
  local module=$1 dir=$2 b
  if [ -n "$(find_record dir "$dir")" ]; then return 0; fi
  if [ -e "$dir" ] || [ -L "$dir" ]; then
    if is_dry; then step "would back up existing $(tilde "$dir") and replace it"; DRY_ADOPTED="$dir"; return 0; fi
    stash "$dir" || return 0
    record "$module" replace "$dir" "$STASHED"
    warn "moved your existing $(tilde "$dir") to $(tilde "$STASHED")"
  elif is_dry; then
    step "would create $dir"; return 0
  fi
  ensure_dir "$module" "$(dirname "$dir")" || return 0
  mkdir -p "$dir" || return 0
  record "$module" dir "$dir"
}

# track_new_dir <module> <dir>: something we are about to run will create <dir>
# (a toolchain home, plugin cache). Record it so undo can remove it.
track_new_dir() {
  local module=$1 dir=$2
  [ -e "$dir" ] && return 0
  [ -n "$(find_record dir "$dir")" ] && return 0
  is_dry && return 0
  ensure_dir "$module" "$(dirname "$dir")"
  record "$module" dir "$dir"
}

# install_file <module> <src> <dest> [mode]
# Writes a devenv-owned file. If you have edited a file devenv wrote earlier,
# your version is left alone unless --force is given (then it is backed up).
install_file() {
  local module=$1 src=$2 dest=$3 mode=${4:-} rec kind cur sha
  sha=$(sha_of "$src")
  # Dry run inside a directory that would have been moved aside: the file is new.
  if is_dry && [ -n "${DRY_ADOPTED:-}" ]; then
    case "$dest" in "$DRY_ADOPTED"/*) step "would create $(tilde "$dest")"; return 0 ;; esac
  fi
  rec=$(find_record file "$dest")
  [ -n "$rec" ] || rec=$(find_record replace "$dest")

  if [ -n "$rec" ]; then
    kind=$(field "$rec" 5)
    cur=$(sha_of "$dest")
    if [ "$cur" = "$sha" ]; then return 0; fi
    if [ "$cur" != "$(field "$rec" 8)" ] && [ "$cur" != none ]; then
      if [ "${FORCE:-0}" != 1 ]; then
        warn "kept your edits to $dest (re-run with --force to replace it; your copy will be backed up)"
        return 0
      fi
      if is_dry; then step "would back up your edited $dest and rewrite it"; return 0; fi
      stash "$dest" || return 0
      history_add "backup of edited $dest -> $STASHED"
      warn "your edited $dest was saved to $STASHED"
    fi
    if is_dry; then step "would update $(tilde "$dest")"; return 0; fi
    ensure_dir "$module" "$(dirname "$dest")" || return 0
    cp "$src" "$dest" || return 0
    [ -n "$mode" ] && chmod "$mode" "$dest"
    record_set "$(field "$rec" 1)" 8 "$sha"
    history_add "update $dest (#$(field "$rec" 1), $kind)"
    ok "updated $(tilde "$dest")"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if is_dry; then step "would back up existing $(tilde "$dest") and replace it"; return 0; fi
    stash "$dest" || return 0
    # Recorded before the copy: if that is skipped, undo still restores the original.
    record "$module" replace "$dest" "$STASHED" "$sha"
    cp "$src" "$dest" || return 0
    [ -n "$mode" ] && chmod "$mode" "$dest"
    ok "replaced $(tilde "$dest") (original saved to $(tilde "$STASHED"))"
  else
    if is_dry; then step "would create $(tilde "$dest")"; return 0; fi
    ensure_dir "$module" "$(dirname "$dest")" || return 0
    cp "$src" "$dest" || return 0
    [ -n "$mode" ] && chmod "$mode" "$dest"
    record "$module" file "$dest" '' "$sha"
    ok "created $(tilde "$dest")"
  fi
}

# remove_file_if_ours <dest>: drop a devenv-owned file that is no longer wanted
# (e.g. the Go plugin spec after `devenv undo go`). Edited files are kept.
remove_file_if_ours() {
  local dest=$1 rec
  rec=$(find_record file "$dest")
  [ -n "$rec" ] || return 0
  undo_record "$rec"
}

# link_file <module> <target> <link>: create a symlink if nothing is there.
link_file() {
  local module=$1 target=$2 link=$3
  if [ -e "$link" ] || [ -L "$link" ]; then return 0; fi
  if is_dry; then step "would link $link -> $target"; return 0; fi
  ensure_dir "$module" "$(dirname "$link")" || return 0
  ln -s "$target" "$link" || return 0
  record "$module" link "$link" "$target"
  ok "linked $(tilde "$link")"
}

BLOCK_BEGIN='# >>> devenv >>> (managed by devenv; remove with `devenv undo shellrc`)'
BLOCK_END='# <<< devenv <<<'

# put_block <module> <file> <content>: add or refresh a marked block at the end
# of a file you own (e.g. ~/.zshrc). Nothing outside the markers is touched.
put_block() {
  local module=$1 file=$2 content=$3 tmp created='' had=''
  [ -f "$file" ] && grep -qF "$BLOCK_BEGIN" "$file" && had=1
  # The new file is built aside and copied over, so --step shows one plain cp.
  tmp=$(scratch)
  if [ -n "$had" ]; then
    strip_block "$file" >"$tmp"
  elif [ -f "$file" ]; then
    cat "$file" >"$tmp"
    # Files without a final newline get one; remembered so undo can take it away.
    if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >>"$tmp"; created='nl'; fi
  else
    created=created
  fi
  printf '\n%s\n%s\n%s\n' "$BLOCK_BEGIN" "$content" "$BLOCK_END" >>"$tmp"
  if cmp -s "$tmp" "$file"; then rm -f "$tmp"; return 0; fi
  if is_dry; then
    rm -f "$tmp"
    if [ -n "$had" ]; then step "would refresh the devenv block in $file"; else step "would add a devenv block to $file"; fi
    return 0
  fi
  if ! ensure_dir "$module" "$(dirname "$file")" || ! cp "$tmp" "$file"; then rm -f "$tmp"; return 0; fi
  rm -f "$tmp"
  if [ -n "$had" ]; then
    history_add "refresh block in $file"
    ok "refreshed the devenv block in $(tilde "$file")"
    [ -n "$(find_record block "$file")" ] || record "$module" block "$file" ''
  else
    record "$module" block "$file" "$created"
    ok "added a devenv block to $(tilde "$file")"
  fi
}

# Print <file> without the devenv block (and the blank line we put before it).
strip_block() {
  awk -v b="$BLOCK_BEGIN" -v e="$BLOCK_END" '
    $0 == b { skip = 1; if (held) held = 0; next }
    skip && $0 == e { skip = 0; next }
    skip { next }
    { if (held) print ""; held = 0; if ($0 == "") { held = 1 } else print }
    END { if (held) print "" }
  ' "$1"
}
