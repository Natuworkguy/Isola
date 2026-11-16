#Requires -Version 5.1
<#
    Isola installer for Windows (PowerShell).

      irm https://raw.githubusercontent.com/Natuworkguy/Isola/main/install.ps1 | iex
      .\install.ps1 -Dev          the dev branch, built from source, where changes land before a release
      .\install.ps1 -Uninstall    take it back out
      & ([scriptblock]::Create((irm https://raw.githubusercontent.com/Natuworkguy/Isola/main/install.ps1))) -Dev

    Installs the latest release for this PC (x64, or ARM64): its installer, run quietly, which needs no administrator
    rights and adds Isola to the Start menu with an uninstaller in Settings, Apps. Where the release has none (or with
    -Dev), it builds Isola from source instead, first installing the .NET 8 SDK for this user if the PC lacks it, and
    puts Isola.exe in %LOCALAPPDATA%\Programs\Isola with a Start menu shortcut. Then it starts Isola. Running it again
    updates.
#>
param([switch]$Dev, [switch]$Uninstall)
$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

$Repo = 'Natuworkguy/Isola'
$Branch = if ($Dev) { 'dev' } else { 'main' }
$Arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64' -or $env:PROCESSOR_ARCHITEW6432 -eq 'ARM64') { 'arm64' } else { 'x64' }
$Home2 = Join-Path $env:LOCALAPPDATA 'Programs\Isola'
$Shortcut = Join-Path ([Environment]::GetFolderPath('Programs')) 'Isola.lnk'

function Stop-Isola { Get-Process -Name Isola -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }

if ($Uninstall) {
    Stop-Isola
    $unins = Get-ChildItem -Path $Home2 -Filter 'unins*.exe' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($unins) { Start-Process -FilePath $unins.FullName -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait }
    if (Test-Path $Home2) { Remove-Item -Recurse -Force $Home2 }
    if (Test-Path $Shortcut) { Remove-Item -Force $Shortcut }
    Write-Host 'Isola is uninstalled.'
    return
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) ("isola-install-" + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $tmp | Out-Null
try {
    $installed = $false

    # 1. The latest release's installer for this PC, run quietly (not for -Dev)
    if (-not $Dev) {
        Write-Host "Downloading the latest release of Isola for Windows ($Arch)."
        $setup = Join-Path $tmp "Isola-Windows-$Arch-Setup.exe"
        try { Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/releases/latest/download/Isola-Windows-$Arch-Setup.exe" -OutFile $setup } catch { $setup = $null }
        if ($setup -and (Test-Path $setup)) {
            Stop-Isola
            Write-Host 'Installing.'
            $p = Start-Process -FilePath $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/CLOSEAPPLICATIONS' -Wait -PassThru
            if ($p.ExitCode -ne 0) { throw "The Isola installer stopped (code $($p.ExitCode))." }
            $installed = $true
        } else {
            Write-Host 'The latest release has no Windows download yet, so Isola will be built from source.'
        }
    }

    # 2. Otherwise, built from source with the .NET 8 SDK
    if (-not $installed) {
        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        $hasSdk = $false
        if ($dotnet) { $hasSdk = [bool](& dotnet --list-sdks 2>$null | Where-Object { $_ -match '^8\.' }) }
        if (-not $hasSdk) {
            Write-Host 'Isola is built with the .NET 8 SDK, which this PC does not have yet. Installing it for you (about 200 MB).'
            $dir = Join-Path $env:LOCALAPPDATA 'Microsoft\dotnet'
            $script = Join-Path $tmp 'dotnet-install.ps1'
            Invoke-WebRequest -UseBasicParsing -Uri 'https://dot.net/v1/dotnet-install.ps1' -OutFile $script
            & $script -Channel 8.0 -InstallDir $dir -NoPath
            $env:DOTNET_ROOT = $dir
            $env:PATH = "$dir;$env:PATH"
            Write-Host 'The .NET 8 SDK is installed.'
        }
        Write-Host "Downloading Isola's source ($Branch)."
        $zip = Join-Path $tmp 'source.zip'
        Invoke-WebRequest -UseBasicParsing -Uri "https://github.com/$Repo/archive/refs/heads/$Branch.zip" -OutFile $zip
        Expand-Archive -Path $zip -DestinationPath $tmp -Force
        $src = Get-ChildItem -Path $tmp -Directory -Filter 'Isola-*' | Select-Object -First 1
        if (-not $src) { throw "Could not unpack Isola's source." }
        Write-Host 'Building Isola. The first build takes a few minutes.'
        Push-Location (Join-Path $src.FullName 'Windows')
        try { & .\build.ps1 -Runtime "win-$Arch" } finally { Pop-Location }
        $exe = Join-Path $src.FullName "Windows\build\win-$Arch\Isola.exe"
        if (-not (Test-Path $exe)) { throw 'The build did not make Isola.exe.' }
        Stop-Isola
        New-Item -ItemType Directory -Force -Path $Home2 | Out-Null
        Copy-Item -Force $exe (Join-Path $Home2 'Isola.exe')
        $shell = New-Object -ComObject WScript.Shell
        $link = $shell.CreateShortcut($Shortcut)
        $link.TargetPath = Join-Path $Home2 'Isola.exe'
        $link.WorkingDirectory = $Home2
        $link.Save()
    }

    $exe = Join-Path $Home2 'Isola.exe'
    if (-not (Test-Path $exe)) { throw "Isola.exe is not where it should be ($exe)." }
    $which = if ($Dev) { ' (the dev version)' } else { '' }
    Write-Host "Isola is installed$which. Starting it: look at the top of your screen."
    Start-Process -FilePath $exe
} finally {
    Remove-Item -Recurse -Force $tmp -ErrorAction SilentlyContinue
}
