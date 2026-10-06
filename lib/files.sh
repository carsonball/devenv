# shellcheck shell=bash
# Tracked file-system changes. Every function here records what it did in the
# manifest so `devenv undo` can reverse it exactly.

backup_path() {
  case "$1" in
    "$HOME"/*) printf '%s/backups/%s/home%s\n' "$STATE_DIR" "${RUN_ID:-manual}" "${1#"$HOME"}" ;;
    *)         printf '%s/backups/%s%s\n' "$STATE_DIR" "${RUN_ID:-manual}" "$1" ;;
  esac
}

# Move whatever sits at <path> into the backup area and print where it went.
stash() {
  local path=$1 dest
  dest=$(backup_path "$path")
  if [ -e "$dest" ] || [ -L "$dest" ]; then dest="$dest.$$.$(date +%s)"; fi
  mkdir -p "$(dirname "$dest")"
  mv "$path" "$dest"
  printf '%s\n' "$dest"
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
    mkdir "$d" && record "$module" mkdir "$d"
  done
}

# adopt_dir <module> <dir>: devenv takes over <dir> entirely. An existing,
# untracked directory is moved to the backup area first.
adopt_dir() {
  local module=$1 dir=$2 b
  if [ -n "$(find_record dir "$dir")" ]; then return 0; fi
  if [ -e "$dir" ] || [ -L "$dir" ]; then
    if is_dry; then step "would back up existing $dir and replace it"; return 0; fi
    b=$(stash "$dir")
    record "$module" replace "$dir" "$b"
    warn "moved your existing $(tilde "$dir") to $(tilde "$b")"
  elif is_dry; then
    step "would create $dir"; return 0
  fi
  ensure_dir "$module" "$(dirname "$dir")"
  mkdir -p "$dir"
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
  local module=$1 src=$2 dest=$3 mode=${4:-} rec kind cur sha b
  sha=$(sha_of "$src")
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
      b=$(stash "$dest")
      history_add "backup of edited $dest -> $b"
      warn "your edited $dest was saved to $b"
    fi
    if is_dry; then step "would update $dest"; return 0; fi
    ensure_dir "$module" "$(dirname "$dest")"
    cp "$src" "$dest"
    [ -n "$mode" ] && chmod "$mode" "$dest"
    record_set "$(field "$rec" 1)" 8 "$sha"
    history_add "update $dest (#$(field "$rec" 1), $kind)"
    ok "updated $(tilde "$dest")"
    return 0
  fi

  if [ -e "$dest" ] || [ -L "$dest" ]; then
    if is_dry; then step "would back up existing $dest and replace it"; return 0; fi
    b=$(stash "$dest")
    cp "$src" "$dest"
    [ -n "$mode" ] && chmod "$mode" "$dest"
    record "$module" replace "$dest" "$b" "$sha"
    ok "replaced $(tilde "$dest") (original saved to $(tilde "$b"))"
  else
    if is_dry; then step "would create $dest"; return 0; fi
    ensure_dir "$module" "$(dirname "$dest")"
    cp "$src" "$dest"
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
  ensure_dir "$module" "$(dirname "$link")"
  ln -s "$target" "$link"
  record "$module" link "$link" "$target"
  ok "linked $(tilde "$link")"
}

BLOCK_BEGIN='# >>> devenv >>> (managed by devenv; remove with `devenv undo shellrc`)'
BLOCK_END='# <<< devenv <<<'

# put_block <module> <file> <content>: add or refresh a marked block at the end
# of a file you own (e.g. ~/.zshrc). Nothing outside the markers is touched.
put_block() {
  local module=$1 file=$2 content=$3 tmp created=''
  if [ -f "$file" ] && grep -qF "$BLOCK_BEGIN" "$file"; then
    tmp=$(mktemp)
    strip_block "$file" >"$tmp"
    printf '\n%s\n%s\n%s\n' "$BLOCK_BEGIN" "$content" "$BLOCK_END" >>"$tmp"
    if cmp -s "$tmp" "$file"; then rm -f "$tmp"; return 0; fi
    if is_dry; then rm -f "$tmp"; step "would refresh the devenv block in $file"; return 0; fi
    cat "$tmp" >"$file"; rm -f "$tmp"
    history_add "refresh block in $file"
    ok "refreshed the devenv block in $(tilde "$file")"
    [ -n "$(find_record block "$file")" ] || record "$module" block "$file" ''
    return 0
  fi
  if is_dry; then step "would add a devenv block to $file"; return 0; fi
  [ -f "$file" ] || created=created
  ensure_dir "$module" "$(dirname "$file")"
  # Files without a final newline get one; remembered so undo can take it away.
  if [ -s "$file" ] && [ -n "$(tail -c 1 "$file")" ]; then printf '\n' >>"$file"; created='nl'; fi
  printf '\n%s\n%s\n%s\n' "$BLOCK_BEGIN" "$content" "$BLOCK_END" >>"$file"
  record "$module" block "$file" "$created"
  ok "added a devenv block to $(tilde "$file")"
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
