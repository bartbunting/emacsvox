param(
    [switch]$Clean,
    [switch]$HelperOnly,
    [string]$OutputDirectory = "bin"
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Common = Join-Path (Split-Path -Parent $Root) "windows-speech-common"
$Bin = Join-Path $Root $OutputDirectory

if ($Clean) {
    if (Test-Path $Bin) {
        Remove-Item -Recurse -Force $Bin
    }
    exit 0
}

$Compiler = Join-Path $env:WINDIR `
    "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (!(Test-Path $Compiler)) {
    throw "The .NET Framework C# compiler was not found at $Compiler"
}

New-Item -ItemType Directory -Force $Bin | Out-Null

& $Compiler /nologo /target:exe /optimize+ /platform:x86 `
    /reference:System.Web.Extensions.dll `
    "/out:$Bin\OmnivoxDectalkHelper32.exe" `
    (Join-Path $Root "OmnivoxDectalkCapture.cs") `
    (Join-Path $Root "OmnivoxDectalkHelper.cs") `
    (Join-Path $Common "OmnivoxHelperHost.cs")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build OmnivoxDectalkHelper32.exe"
}

if (!$HelperOnly) {
    $BridgeSources = @(
        (Join-Path $Root "DectalkBridge.cs"),
        (Join-Path $Common "BridgeProtocol.cs"),
        (Join-Path $Common "WaveOutPlayer.cs")
    )
    & $Compiler /nologo /target:exe /optimize+ /platform:x86 `
        "/out:$Bin\DectalkBridge32.exe" $BridgeSources
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build DectalkBridge32.exe"
    }

    & $Compiler /nologo /target:exe /optimize+ /platform:x64 `
        "/out:$Bin\DectalkBridge.exe" `
        (Join-Path $Root "DectalkBridgeLauncher.cs") `
        (Join-Path $Common "BridgeLauncher.cs")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build DectalkBridge.exe"
    }
}

if ($HelperOnly) {
    Write-Output "Built Omnivox DECtalk helper under $Bin"
} else {
    Write-Output "Built DECtalk bridges and Omnivox helper under $Bin"
}
