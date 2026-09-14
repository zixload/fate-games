<#
    Lance le banc de test hors-jeu.

        .\scripts\test.ps1

    Ne demarre pas le serveur : les globales du moteur sont bouchonnees.
    Code de sortie 0 si tout passe, 1 sinon.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$repo = Split-Path $PSScriptRoot -Parent

$lua = $null
$onPath = Get-Command lua -ErrorAction SilentlyContinue
if ($onPath) {
    $lua = $onPath.Source
} else {
    # winget installe DEVCOM.Lua ici ; le PATH n'est visible qu'apres un nouveau shell
    $fallback = Join-Path $env:LOCALAPPDATA "Programs\Lua\bin\lua.exe"
    if (Test-Path $fallback) { $lua = $fallback }
}

if (-not $lua) {
    Write-Host "interpreteur Lua introuvable. Installer avec :" -ForegroundColor Red
    Write-Host "    winget install --id DEVCOM.Lua --exact"
    exit 1
}

Push-Location $repo
try {
    & $lua "tests/run.lua"
    $code = $LASTEXITCODE
} finally {
    Pop-Location
}

exit $code
