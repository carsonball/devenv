# shellcheck shell=bash
# The manifest is the source of truth for everything devenv changed.
#
#   $STATE_DIR/manifest.tsv   one line per live change (removed when undone)
#   $STATE_DIR/history.log    append-only log of every change and every undo
#   $STATE_DIR/modules        modules currently installed, one per line
#   $STATE_DIR/excluded       core modules the user undid (not re-added implicitly)
#   $STATE_DIR/backups/       originals of every file or directory we replaced
#   $STATE_DIR/runs/          full command output of each run
#
# manifest.tsv columns (tab separated):
#   seq  time  run  module  kind  target  data  sha
#   (sha = content hash of files we wrote, used to notice your later edits)
#
# kinds:
#   brew <formula>          formula we installed           undo: brew uninstall
#   cask <cask>             cask we installed              undo: brew uninstall --cask
#   apt <package>           apt package we installed       undo: apt-get remove
#   winget <id>             Windows app we installed       undo: winget uninstall
#   homebrew <prefix>       Homebrew itself                undo: official uninstaller
#   file <path> <sha>       file we created                undo: delete (kept if you edited it)
#   replace <path> <backup> file/dir that existed before   undo: put the original back
#   dir <path>              directory we created           undo: delete it
#   mkdir <path>            parent directory we created    undo: delete it if empty
#   link <path> <target>    symlink we created             undo: delete it
#   block <path> <marker>   marked block added to a file   undo: remove the block
#   plugin <name@market>    Claude Code plugin we installed  undo: claude plugin uninstall
#   marketplace <name>      Claude Code plugin marketplace   undo: claude plugin marketplace remove
#   daemon <name>           background service a tool set up undo: daemon_remove in hooks.sh

STATE_DIR=${DEVENV_STATE_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/devenv}
MANIFEST="$STATE_DIR/manifest.tsv"
HISTORY="$STATE_DIR/history.log"
# shellcheck disable=SC2034
TAB=$(printf '\t')

state_init() {
  is_dry && return 0
  mkdir -p "$STATE_DIR/backups" "$STATE_DIR/runs"
  [ -f "$MANIFEST" ] || : >"$MANIFEST"
  [ -f "$HISTORY" ] || : >"$HISTORY"
  [ -f "$STATE_DIR/modules" ] || : >"$STATE_DIR/modules"
  [ -f "$STATE_DIR/excluded" ] || : >"$STATE_DIR/excluded"
  [ -f "$STATE_DIR/seq" ] || echo 0 >"$STATE_DIR/seq"
}

new_run_id() { date -u +%Y%m%d-%H%M%S; }

history_add() {
  is_dry && return 0
  printf '%s\t%s\t%s\n' "$(now)" "${RUN_ID:-manual}" "$*" >>"$HISTORY"
}

# record <module> <kind> <target> [data] [sha]
record() {
  is_dry && return 0
  local seq
  seq=$(( $(cat "$STATE_DIR/seq") + 1 ))
  echo "$seq" >"$STATE_DIR/seq"
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$seq" "$(now)" "${RUN_ID:-manual}" "$1" "$2" "$3" "${4:-}" "${5:-}" >>"$MANIFEST"
  history_add "do #$seq [$1] $2 $3 ${4:-}"
}

# Print manifest lines whose <field> equals <value>. Fields: 1 seq, 3 run, 4 module, 5 kind, 6 target.
records_where() {
  [ -f "$MANIFEST" ] || return 0
  awk -F'\t' -v f="$1" -v v="$2" '$f == v' "$MANIFEST"
}

# Latest record for kind+target, if any.
find_record() {
  [ -f "$MANIFEST" ] || return 0
  awk -F'\t' -v k="$1" -v t="$2" '$5 == k && $6 == t' "$MANIFEST" | tail -n 1
}

field() { printf '%s\n' "$1" | cut -f"$2"; }

# Rewrite one column of the record with the given seq.
record_set() {
  is_dry && return 0
  local seq=$1 col=$2 val=$3 tmp
  tmp=$(mktemp "$STATE_DIR/.manifest.XXXXXX")
  awk -F'\t' -v OFS='\t' -v s="$seq" -v c="$col" -v v="$val" '$1 == s { $c = v } { print }' "$MANIFEST" >"$tmp" && mv "$tmp" "$MANIFEST"
}

record_delete() {
  is_dry && return 0
  local tmp
  tmp=$(mktemp "$STATE_DIR/.manifest.XXXXXX")
  awk -F'\t' -v s="$1" '$1 != s' "$MANIFEST" >"$tmp" && mv "$tmp" "$MANIFEST"
}

# --- module sets ----------------------------------------------------------

set_list()     { [ -f "$STATE_DIR/$1" ] && grep -v '^$' "$STATE_DIR/$1"; return 0; }
set_has()      { set_list "$1" | grep -qx "$2"; }
set_add() {
  is_dry && return 0
  set_has "$1" "$2" || echo "$2" >>"$STATE_DIR/$1"
}
set_remove() {
  is_dry && return 0
  [ -f "$STATE_DIR/$1" ] || return 0
  local tmp
  tmp=$(mktemp "$STATE_DIR/.set.XXXXXX")
  grep -vx "$2" "$STATE_DIR/$1" >"$tmp"
  mv "$tmp" "$STATE_DIR/$1"
}

active_modules() { set_list modules | tr '\n' ' '; }
