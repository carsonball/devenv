#!/bin/bash
# End-to-end tests against a throwaway $HOME with fake brew/winget/dpkg.
# Nothing here touches the real machine.  Usage: tests/run.sh [-v]
# Runs under any bash >= 3.2 (BASH=/path/to/bash tests/run.sh to pick one).

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SH=${BASH_UNDER_TEST:-bash}
VERBOSE=0; [ "${1:-}" = -v ] && VERBOSE=1
PASS=0 FAIL=0 CURRENT=''
WORK=$(mktemp -d "${TMPDIR:-/tmp}/devenv-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# --- harness ----------------------------------------------------------------

setup() { # setup <name> <os: darwin|linux|wsl>
  CURRENT=$1
  T="$WORK/$1"
  mkdir -p "$T/home" "$T/brew/bin" "$T/fakes" "$T/win"
  cp -R "$ROOT" "$T/devenv"
  cp "$ROOT/tests/fakes/brew" "$T/brew/bin/brew"
  cp "$ROOT/tests/fakes/dpkg" "$ROOT/tests/fakes/cmd.exe" "$T/fakes/"
  chmod +x "$T/brew/bin/brew" "$T/fakes/"*
  mkdir -p "$T/brew/fakedb"
  case $2 in
    darwin) ENVV="DEVENV_OS=darwin DEVENV_ARCH=arm64 SHELL=/bin/zsh DEVENV_WSL=0" ;;
    linux)  ENVV="DEVENV_OS=linux DEVENV_ARCH=x86_64 SHELL=/bin/bash DEVENV_WSL=0" ;;
    wsl)    ENVV="DEVENV_OS=linux DEVENV_ARCH=x86_64 SHELL=/bin/bash DEVENV_WSL=1 WSL_DISTRO_NAME=Ubuntu DEVENV_WINHOME=$T/win FAKE_WIN_DB=$T/win"
            cp "$ROOT/tests/fakes/winget.exe" "$T/fakes/"; chmod +x "$T/fakes/winget.exe" ;;
  esac
}

dev() { # run devenv in the sandbox; output in $OUT, status in $RC
  # shellcheck disable=SC2086
  OUT=$(cd "$T" && env -i HOME="$T/home" PATH="$T/fakes:/usr/bin:/bin" TERM=dumb NO_COLOR=1 \
    DEVENV_BREW_PREFIX="$T/brew" $ENVV ${EXTRA:-} "$SH" "$T/devenv/bin/devenv" "$@" 2>&1)
  RC=$?
  [ "$VERBOSE" = 1 ] && printf '%s\n' "$OUT" | sed 's/^/      | /'
  return 0
}

ok()   { PASS=$((PASS + 1)); [ "$VERBOSE" = 1 ] && echo "  ok   $CURRENT: $1"; return 0; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL $CURRENT: $1"; [ -n "${2:-}" ] && printf '%s\n' "$2" | sed 's/^/       /' | head -40; return 0; }
check() { local d=$1; shift; if "$@"; then ok "$d"; else bad "$d" "$OUT"; fi; }
has_out() { case "$OUT" in *"$1"*) return 0 ;; esac; return 1; }
installed() { grep -qx "$1" "$T/brew/fakedb/formulae"; }
cask_installed() { grep -qx "$1" "$T/brew/fakedb/casks" 2>/dev/null; }
manifest() { cat "$T/home/.local/state/devenv/manifest.tsv"; }
records() { manifest | grep -c .; }

# Content fingerprint of $HOME, ignoring devenv's own state.
snapshot() {
  (cd "$T/home" && find . \( -path ./.local/state -prune \) -o -print | grep -v '^\./\.local$' | sort | while IFS= read -r f; do
    if [ -L "$f" ]; then echo "L $f -> $(readlink "$f")"
    elif [ -f "$f" ]; then echo "F $f $(cksum <"$f")"
    else echo "D $f"; fi
  done)
}

# --- tests ------------------------------------------------------------------

t_mac_install_and_full_undo() {
  setup mac darwin
  mkdir -p "$T/home/.config/nvim/lua"
  echo 'print("my old config")' >"$T/home/.config/nvim/init.lua"
  printf 'export FOO=1\nalias ll="ls -l"' >"$T/home/.zshrc"   # no trailing newline
  echo 'set -g prefix C-b' >"$T/home/.tmux.conf"
  echo git >"$T/brew/fakedb/formulae"                          # you already had git
  local before; before=$(snapshot)

  dev install go ts docker -y --no-sync
  check "install succeeds" [ "$RC" = 0 ]
  check "go installed and recorded" sh -c "grep -qx go '$T/brew/fakedb/formulae' && grep -q '	go	brew	go	' '$T/home/.local/state/devenv/manifest.tsv'"
  check "pre-existing git not recorded" sh -c "! grep -q '	brew	git	' '$T/home/.local/state/devenv/manifest.tsv'"
  check "wezterm cask installed" cask_installed wezterm
  check "nerd font cask installed" cask_installed font-jetbrains-mono-nerd-font
  check "wezterm uses the nerd font" grep -q '"JetBrainsMono Nerd Font"' "$T/home/.config/wezterm/wezterm.lua"
  check "colima on macOS" installed colima
  check "go extra enabled" grep -q 'extras.lang.go"' "$T/home/.config/nvim/lua/devenv/extras.lua"
  check "typescript spec written" [ -f "$T/home/.config/nvim/lua/devenv/plugins/typescript.lua" ]
  check "old nvim config backed up" sh -c "grep -rqs 'my old config' '$T/home/.local/state/devenv/backups'"
  check "home .tmux.conf moved aside" [ ! -e "$T/home/.tmux.conf" ]
  check "tmux.conf written" grep -q 'prefix C-a' "$T/home/.config/tmux/tmux.conf"
  check "zshrc keeps user lines" grep -q 'alias ll="ls -l"' "$T/home/.zshrc"
  check "zshrc sources devenv" grep -q 'devenv/shell.sh' "$T/home/.zshrc"
  check "shell.sh has go path" grep -q 'GOPATH' "$T/home/.config/devenv/shell.sh"
  check "shell.sh has brew path" grep -q "$T/brew/bin/brew" "$T/home/.config/devenv/shell.sh"
  check "compose plugin linked" [ -L "$T/home/.docker/cli-plugins/docker-compose" ]
  check "wezterm config for mac" grep -q 'font_size = 14' "$T/home/.config/wezterm/wezterm.lua"
  check "colima note shown" has_out "colima start"

  local n; n=$(records)
  dev install go -y --no-sync
  check "re-run is idempotent" [ "$(records)" = "$n" ]
  check "re-run says nothing new" has_out "already set up"
  check "re-run rewrites nothing" sh -c "! printf '%s' \"\$0\" | grep -qE 'refreshed|updated|created|replaced'" "$OUT"

  dev status
  check "status lists modules" has_out "Modules: cli shellrc tmux nvim wezterm go typescript docker"
  check "status shows replaced original" has_out "original:"

  dev undo --all -y
  check "undo --all succeeds" [ "$RC" = 0 ]
  check "everything restored byte for byte" [ "$(snapshot)" = "$before" ]
  [ "$(snapshot)" = "$before" ] || diff <(echo "$before") <(snapshot) | sed 's/^/       /'
  check "brew back to what you had" [ "$(cat "$T/brew/fakedb/formulae")" = git ]
  check "casks removed" sh -c "! grep -q . '$T/brew/fakedb/casks'"
  check "manifest empty" [ "$(records)" = 0 ]
  check "history kept" grep -q 'undo #1 ' "$T/home/.local/state/devenv/history.log"
}

t_undo_one_module() {
  setup undomod darwin
  dev install go docker -y --no-sync
  dev undo docker -y
  check "undo docker succeeds" [ "$RC" = 0 ]
  check "colima removed" sh -c "! grep -qx colima '$T/brew/fakedb/formulae'"
  check "go kept" installed go
  check "docker extra dropped" sh -c "! grep -q lang.docker '$T/home/.config/nvim/lua/devenv/extras.lua'"
  check "go extra kept" grep -q lang.go "$T/home/.config/nvim/lua/devenv/extras.lua"
  check "plugin link removed" [ ! -e "$T/home/.docker/cli-plugins/docker-compose" ]
  check "empty ~/.docker cleaned up" [ ! -e "$T/home/.docker" ]
  check "docker no longer active" sh -c "! grep -qx docker '$T/home/.local/state/devenv/modules'"
  dev install docker -y --no-sync
  check "docker can come back" grep -q lang.docker "$T/home/.config/nvim/lua/devenv/extras.lua"
  dev undo --last -y
  check "undo --last" sh -c "! grep -qx colima '$T/brew/fakedb/formulae'"
}

t_module_spec_files_follow_modules() {
  setup specs darwin
  dev install ts k8s -y --no-sync
  check "k8s spec written" [ -f "$T/home/.config/nvim/lua/devenv/plugins/k8s.lua" ]
  check "k8s shell aliases" grep -q 'alias k=kubectl' "$T/home/.config/devenv/shell.sh"
  dev undo k8s -y
  check "k8s spec removed" [ ! -f "$T/home/.config/nvim/lua/devenv/plugins/k8s.lua" ]
  check "k8s aliases removed" sh -c "! grep -q 'alias k=kubectl' '$T/home/.config/devenv/shell.sh'"
  check "ts spec kept" [ -f "$T/home/.config/nvim/lua/devenv/plugins/typescript.lua" ]
}

t_user_edits_are_respected() {
  setup edits darwin
  dev install -y --no-sync
  echo '# my tweak' >>"$T/home/.config/tmux/tmux.conf"
  echo 'return { { "my/plugin" } }' >"$T/home/.config/nvim/lua/plugins/user.lua"
  dev install go -y --no-sync
  check "edited tmux.conf kept" grep -q 'my tweak' "$T/home/.config/tmux/tmux.conf"
  check "warned about edit" has_out "kept your edits"
  check "user.lua never rewritten" grep -q my/plugin "$T/home/.config/nvim/lua/plugins/user.lua"
  dev install --force -y --no-sync
  check "--force rewrites" sh -c "! grep -q 'my tweak' '$T/home/.config/tmux/tmux.conf'"
  check "--force backs up your copy" sh -c "grep -rqs 'my tweak' '$T/home/.local/state/devenv/backups'"
  echo '# again' >>"$T/home/.config/tmux/tmux.conf"
  dev undo --all -y
  check "undo keeps your edited copy in backups" has_out "your version is saved"
  check "edited user.lua saved, not lost" sh -c "grep -rqs my/plugin '$T/home/.local/state/devenv/backups'"
}

t_shared_packages() {
  setup shared darwin
  printf 'desc=A\nrequires=nvim\nbrew=sharedpkg onlya\n' >"$T/devenv/modules/testa.conf"
  printf 'desc=B\nrequires=nvim\nbrew=sharedpkg\n' >"$T/devenv/modules/testb.conf"
  dev install testa testb -y --no-sync
  dev undo testa -y
  check "shared package kept" installed sharedpkg
  check "a's own package removed" sh -c "! grep -qx onlya '$T/brew/fakedb/formulae'"
  check "ownership moved to b" sh -c "grep -q '	testb	brew	sharedpkg' '$T/home/.local/state/devenv/manifest.tsv'"
  dev undo testb -y
  check "removed once nobody needs it" sh -c "! grep -qx sharedpkg '$T/brew/fakedb/formulae'"
}

t_failures_are_reported() {
  setup fails darwin
  EXTRA="FAKE_BREW_FAIL=lazydocker" dev install docker -y --no-sync
  check "others still install" installed colima
  check "failure reported" has_out "did not complete: brew:lazydocker"
  check "failed one not recorded" sh -c "! grep -q '	lazydocker	' '$T/home/.local/state/devenv/manifest.tsv'"
  EXTRA="FAKE_BREW_DEPENDED=go" dev install go -y --no-sync
  EXTRA="FAKE_BREW_DEPENDED=go" dev undo go -y
  check "undo reports what it could not do" [ "$RC" != 0 ]
  check "go stays in manifest for retry" grep -q '	brew	go	' "$T/home/.local/state/devenv/manifest.tsv"
  dev undo --id "$(grep '	brew	go	' "$T/home/.local/state/devenv/manifest.tsv" | cut -f1)" -y
  check "retry by id works" sh -c "! grep -qx go '$T/brew/fakedb/formulae'"
}

t_core_module_undo_sticks() {
  setup core darwin
  echo 'set -g prefix C-b' >"$T/home/.tmux.conf"
  dev install -y --no-sync
  dev undo tmux -y
  check "undoing tmux also undoes wezterm (depends on it)" sh -c "! grep -qx wezterm '$T/home/.local/state/devenv/modules'"
  check "your ~/.tmux.conf is back" grep -q 'prefix C-b' "$T/home/.tmux.conf"
  dev install go -y --no-sync
  check "tmux not re-added implicitly" sh -c "! grep -qx tmux '$T/home/.local/state/devenv/modules'"
  dev install tmux -y --no-sync
  check "explicit install brings it back" grep -qx tmux "$T/home/.local/state/devenv/modules"
}

t_dry_run_changes_nothing() {
  setup dry darwin
  mkdir -p "$T/home/.config/nvim"; echo x >"$T/home/.config/nvim/init.lua"
  local before; before=$(snapshot)
  dev plan go rust
  check "plan succeeds" [ "$RC" = 0 ]
  check "plan lists packages" has_out "would brew install go"
  check "plan mentions backup" has_out "would back up existing"
  check "plan changes nothing" [ "$(snapshot)" = "$before" ]
  check "no state written" [ ! -e "$T/home/.local/state/devenv" ]
  check "no brew calls that install" sh -c "! grep -q 'install' '$T/brew/fakedb/calls' 2>/dev/null"
}

t_wsl() {
  setup wsl wsl
  echo '# ubuntu bashrc' >"$T/home/.bashrc"
  local before; before=$(snapshot)
  dev install go k8s -y --no-sync
  check "wsl install succeeds" [ "$RC" = 0 ]
  check "wezterm via winget" grep -qx wez.wezterm "$T/win/winget"
  check "nerd font via winget" grep -qx DEVCOM.JetBrainsMonoNerdFont "$T/win/winget"
  check "no casks on linux" sh -c "! grep -q . '$T/brew/fakedb/casks' 2>/dev/null"
  check "no colima on linux" sh -c "! grep -qx colima '$T/brew/fakedb/formulae'"
  check "wezterm config on Windows side" grep -q 'wsl_distro = "Ubuntu"' "$T/win/.config/wezterm/wezterm.lua"
  check "bashrc hook" grep -q 'devenv/shell.sh' "$T/home/.bashrc"
  dev undo --all -y
  check "winget app removed" sh -c "! grep -q . '$T/win/winget'"
  check "windows config removed" [ ! -e "$T/win/.config" ]
  check "linux home restored" [ "$(snapshot)" = "$before" ]
}

t_word_resolution() {
  setup words darwin
  dev plan .tsx Dockerfile kubernetes golang .py
  check "aliases resolve" sh -c "printf '%s' \"\$0\" | grep -q 'typescript' && printf '%s' \"\$0\" | grep -q 'python'" "$OUT"
  dev plan cobol
  check "unknown word fails" [ "$RC" = 2 ]
  check "unknown word explained" has_out "don't know how to set up: cobol"
}

t_diff_and_log() {
  setup diff darwin
  mkdir -p "$T/home/.config/wezterm"; echo 'return {}' >"$T/home/.config/wezterm/wezterm.lua"
  dev install -y --no-sync
  dev diff "$T/home/.config/wezterm/wezterm.lua"
  check "diff shows original vs new" sh -c "printf '%s' \"\$0\" | grep -q '^-return {}'" "$OUT"
  dev log
  check "log has entries" has_out "do #1 "
}

t_repo_file_modes() {
  CURRENT=modes
  # Executables must be committed as such: the install tarball comes from git.
  if git -C "$ROOT" rev-parse >/dev/null 2>&1; then
    local f
    for f in bin/devenv install.sh templates/tmux/tmux-sessionizer; do
      check "$f committed executable" sh -c "git -C '$ROOT' ls-files -s '$f' | grep -q '^100755'"
    done
  fi
}

for t in $(declare -F | awk '{print $3}' | grep '^t_'); do
  [ "$VERBOSE" = 1 ] && echo "== $t"
  $t
done
echo "$PASS passed, $FAIL failed ($("$SH" -c 'echo $BASH_VERSION'))"
[ "$FAIL" = 0 ]
