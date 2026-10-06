<#
  devenv bootstrap for Windows. WezTerm runs natively on Windows; the shell,
  tmux and Neovim run in WSL (tmux has no native Windows build).

  From a PowerShell prompt:
    & ([scriptblock]::Create((irm https://raw.githubusercontent.com/carsonball/devenv/main/bootstrap.ps1))) go docker k8s ts

  Or from a local copy (no GitHub needed):
    powershell -ExecutionPolicy Bypass -File .\bootstrap.ps1 -Source . go docker k8s ts

  What it does:
    1. Makes sure WSL and an Ubuntu distro exist (installs them if not; Windows may ask to reboot).
    2. Runs devenv inside Ubuntu. devenv installs WezTerm on Windows through winget,
       writes its config to %USERPROFILE%\.config\wezterm, and records both so
       `devenv undo` can remove them.
#>
param(
  [string]$Repo = $(if ($env:DEVENV_REPO) { $env:DEVENV_REPO } else { 'carsonball/devenv' }),
  [string]$Distro = 'Ubuntu',
  [string]$Source = '',
  [Parameter(ValueFromRemainingArguments = $true)][string[]]$Modules
)
$ErrorActionPreference = 'Stop'

function Say($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
  throw 'wsl.exe not found. devenv needs Windows 10 2004+ or Windows 11.'
}

# `wsl -l -q` prints UTF-16; strip the NULs so the names compare cleanly.
$distros = @(& wsl.exe --list --quiet 2>$null | ForEach-Object { ($_ -replace "`0", '').Trim() } | Where-Object { $_ })
if ($distros -notcontains $Distro) {
  Say "Installing WSL with $Distro (Windows may ask for admin rights and a reboot)"
  & wsl.exe --install -d $Distro
  Write-Host ''
  Write-Host "When $Distro has opened and you have created your Linux user, run this script again."
  exit 0
}

$argLine = ($Modules | ForEach-Object { "'" + ($_ -replace "'", '') + "'" }) -join ' '
if ($Source) {
  $full = (Resolve-Path $Source).Path
  $wslPath = (& wsl.exe -d $Distro -- wslpath -a ($full -replace '\\', '/')).Trim()
  Say "Running devenv from $full inside $Distro"
  & wsl.exe -d $Distro -- bash -lc "bash '$wslPath/install.sh' $argLine"
} else {
  Say "Running devenv inside $Distro"
  & wsl.exe -d $Distro -- bash -lc "curl -fsSL https://raw.githubusercontent.com/$Repo/main/install.sh | DEVENV_REPO='$Repo' bash -s -- $argLine"
}
if ($LASTEXITCODE -ne 0) { throw "devenv exited with $LASTEXITCODE" }

Say 'Done. Open WezTerm from the Start menu: it starts in tmux inside WSL.'
