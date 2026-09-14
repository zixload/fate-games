<#
    Boucle de developpement.

    Usage :
        .\scripts\dev.ps1 start      demarre en capturant la sortie dans .dev\server.log
        .\scripts\dev.ps1 console    demarre dans une fenetre interactive
        .\scripts\dev.ps1 stop       arrete le serveur
        .\scripts\dev.ps1 restart    redemarre en mode capture
        .\scripts\dev.ps1 status     etat du processus et du package monte
        .\scripts\dev.ps1 use        monte ce depot sur le serveur, sans demarrer
        .\scripts\dev.ps1 logs       40 dernieres lignes
        .\scripts\dev.ps1 logs -Follow   suit la sortie en continu

    Plusieurs depots partagent la meme installation de serveur. Avant chaque
    demarrage, le script s'assure que c'est CE package qui est monte et charge :
    la jonction est posee si besoin, et Config.toml est reecrit pour ne charger
    que lui. Lancer dev.ps1 depuis un autre depot bascule donc automatiquement.

    Deux modes, parce qu'on ne peut pas avoir les deux a la fois sous Windows :
    `start` capture la sortie dans un fichier mais n'a pas de console ou taper des
    commandes ; `console` ouvre la vraie console du serveur, ou se tape le
    rechargement a chaud :

        package reload all

    A savoir : le fichier de log du moteur (.logs\NanosWorldCore.log) reste a 0
    octet tant que le serveur tourne, meme avec 'async_log = false'. D'ou la
    capture de la sortie standard plutot que la lecture de ce fichier.
#>

[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet("start", "console", "stop", "restart", "status", "use", "logs")]
    [string]$Action = "status",

    [int]$Lines = 40,
    [switch]$Follow
)

$ErrorActionPreference = "Stop"

$ServerDir = "C:\nanos-world-server"
$Exe       = Join-Path $ServerDir "NanosWorldServer.exe"
$DevDir    = Join-Path $ServerDir ".dev"
$OutFile   = Join-Path $DevDir "server.log"
$Config    = Join-Path $ServerDir "Config.toml"

$Repo = Split-Path $PSScriptRoot -Parent

# Le nom du package est celui du seul dossier sous Packages/.
$PackageDir = Get-ChildItem (Join-Path $Repo "Packages") -Directory | Select-Object -First 1
if (-not $PackageDir) { throw "aucun package dans $Repo\Packages" }
$Package = $PackageDir.Name

function Get-ServerProcess {
    Get-Process -Name "NanosWorldServer" -ErrorAction SilentlyContinue
}

function Stop-Server {
    $procs = Get-ServerProcess
    if (-not $procs) { Write-Host "aucune instance en cours"; return }
    foreach ($p in $procs) {
        Write-Host "arret de PID $($p.Id)"
        Stop-Process -Id $p.Id -Force
    }
    Start-Sleep -Seconds 2
}

# Pose la jonction si besoin et fait charger ce package, et lui seul.
function Use-ThisPackage {
    $link   = Join-Path $ServerDir "Packages\$Package"
    $target = $PackageDir.FullName

    if (-not (Test-Path $link)) {
        cmd /c mklink /J "$link" "$target" | Out-Null
        Write-Host "jonction posee : $link" -ForegroundColor Green
    }

    # Lecture en UTF-8 explicite : Get-Content suivrait la page de codes de la
    # console, qui n'est pas forcement UTF-8 et corromprait les accents.
    $text = [System.IO.File]::ReadAllText($Config)
    $wanted = "    packages = [`r`n                             `"$Package`",`r`n    ]"
    $updated = [System.Text.RegularExpressions.Regex]::Replace(
        $text, '    packages = \[[^\]]*\]', $wanted)

    if ($updated -ne $text) {
        [System.IO.File]::WriteAllText($Config, $updated, (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "Config.toml charge desormais '$Package'" -ForegroundColor Green
    }
}

function Show-Logs {
    param([int]$Count = 40, [switch]$Wait)
    if (-not (Test-Path $OutFile)) {
        Write-Host "pas de sortie capturee : demarrer avec 'dev.ps1 start'" -ForegroundColor Yellow
        return
    }
    if ($Wait) { Get-Content $OutFile -Tail $Count -Wait } else { Get-Content $OutFile -Tail $Count }
}

function Assert-Binary {
    if (-not (Test-Path $Exe)) { throw "binaire introuvable : $Exe" }
}

function Start-Captured {
    if (Get-ServerProcess) { Stop-Server }
    Assert-Binary
    Use-ThisPackage

    if (-not (Test-Path $DevDir)) { New-Item -ItemType Directory $DevDir | Out-Null }

    $proc = Start-Process -FilePath $Exe -WorkingDirectory $ServerDir `
        -PassThru -WindowStyle Hidden -RedirectStandardOutput $OutFile
    Write-Host "demarre en mode capture, PID $($proc.Id)"

    for ($i = 0; $i -lt 40; $i++) {
        Start-Sleep -Seconds 1
        if ($proc.HasExited) {
            Write-Host "le serveur s'est arrete (code $($proc.ExitCode))" -ForegroundColor Red
            Show-Logs -Count 20
            return
        }
        $started = $false
        if (Test-Path $OutFile) {
            try   { $started = Select-String -Path $OutFile -Pattern "Server started" -Quiet }
            catch { $started = $false }
        }
        if ($started) {
            Write-Host "serveur pret en $($i + 1)s" -ForegroundColor Green
            Show-Logs -Count $Lines
            return
        }
    }

    Write-Host "pas de 'Server started' apres 40s" -ForegroundColor Yellow
    Show-Logs -Count $Lines
}

function Start-Console {
    if (Get-ServerProcess) { Stop-Server }
    Assert-Binary
    Use-ThisPackage

    $proc = Start-Process -FilePath $Exe -WorkingDirectory $ServerDir -PassThru
    Write-Host "demarre en console interactive, PID $($proc.Id)"
    Write-Host "rechargement a chaud : taper 'package reload all' dans la fenetre" -ForegroundColor Cyan
}

function Show-Status {
    Write-Host "package de ce depot : $Package"
    $procs = Get-ServerProcess
    if ($procs) {
        foreach ($p in $procs) {
            Write-Host "en cours : PID $($p.Id), demarre a $($p.StartTime)" -ForegroundColor Green
        }
    } else {
        Write-Host "arrete"
    }
    if (Test-Path $Config) {
        $loaded = [System.IO.File]::ReadAllText($Config)
        if ($loaded -match '"([a-z0-9\-]+)",') {
            Write-Host "Config.toml charge : $($Matches[1])"
        }
    }
}

switch ($Action) {
    "start"   { Start-Captured }
    "console" { Start-Console }
    "stop"    { Stop-Server }
    "restart" { Stop-Server; Start-Captured }
    "use"     { Use-ThisPackage }
    "status"  { Show-Status }
    "logs"    { Show-Logs -Count $Lines -Wait:$Follow }
}
