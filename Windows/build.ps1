<#
.SYNOPSIS
    Builds Isola for Windows into build\<runtime>\Isola.exe and build\Isola-Windows-<arch>.zip, and with -Installer
    build\Isola-Windows-<arch>-Setup.exe too (needs Inno Setup 6).

.EXAMPLE
    .\build.ps1                          # x64, self-contained (no .NET needed to run it)
    .\build.ps1 -Runtime win-arm64
    .\build.ps1 -Version 1.2.0
    .\build.ps1 -Installer               # also the installer, from installer.iss
    .\build.ps1 -FrameworkDependent      # much smaller; needs the .NET 8 Desktop Runtime to run
#>
param(
    [ValidateSet("win-x64", "win-arm64")] [string] $Runtime = "win-x64",
    [string] $Version = "",
    [switch] $FrameworkDependent,
    [switch] $Installer
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

$out = Join-Path "build" $Runtime
if (Test-Path $out) { Remove-Item $out -Recurse -Force }

$publish = @(
    "publish", "Isola/Isola.csproj", "-c", "Release", "-r", $Runtime,
    "--self-contained", $(if ($FrameworkDependent) { "false" } else { "true" }),
    "-p:PublishSingleFile=true", "-p:IncludeNativeLibrariesForSelfExtract=true", "-o", $out
)
if (-not $FrameworkDependent) { $publish += "-p:EnableCompressionInSingleFile=true" }
if ($Version) { $publish += "-p:Version=$Version" }

dotnet @publish
if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed" }

$arch = $Runtime.Substring(4)
$zip = Join-Path "build" "Isola-Windows-$arch.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path (Join-Path $out "Isola.exe") -DestinationPath $zip

Write-Host "Built $out\Isola.exe"
Write-Host "Zipped $zip"

if ($Installer) {
    $iscc = (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source
    if (-not $iscc) { $iscc = Join-Path ${env:ProgramFiles(x86)} "Inno Setup 6\ISCC.exe" }
    if (-not (Test-Path $iscc)) { throw "Inno Setup 6 is not installed (https://jrsoftware.org/isdl.php)" }
    # The installer's version: -Version, or the project's own.
    $appVersion = $Version
    if (-not $appVersion) { $appVersion = ([xml](Get-Content "Isola/Isola.csproj")).Project.PropertyGroup.Version | Select-Object -First 1 }
    & $iscc "/Q" "/DArch=$arch" "/DVersion=$appVersion" "installer.iss"
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed" }
    Write-Host "Built build\Isola-Windows-$arch-Setup.exe"
}
