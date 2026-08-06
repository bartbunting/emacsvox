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
    "/out:$Bin\OmnivoxEloquenceHelper32.exe" `
    (Join-Path $Root "OmnivoxEloquenceCapture.cs") `
    (Join-Path $Root "OmnivoxEloquenceHelper.cs")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build OmnivoxEloquenceHelper32.exe"
}

if (!$HelperOnly) {
    $BridgeSources = @(
        (Join-Path $Root "EloquenceBridge.cs"),
        (Join-Path $Common "BridgeProtocol.cs"),
        (Join-Path $Common "WaveOutPlayer.cs")
    )
    & $Compiler /nologo /target:exe /optimize+ /platform:x86 `
        "/out:$Bin\EloquenceBridge32.exe" $BridgeSources
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build EloquenceBridge32.exe"
    }

    & $Compiler /nologo /target:exe /optimize+ /platform:x64 `
        "/out:$Bin\EloquenceBridge.exe" `
        (Join-Path $Root "EloquenceBridgeLauncher.cs") `
        (Join-Path $Common "BridgeLauncher.cs")
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build EloquenceBridge.exe"
    }
}

if ($HelperOnly) {
    Write-Output "Built Omnivox Eloquence helper under $Bin"
} else {
    Write-Output "Built Eloquence bridges and Omnivox helper under $Bin"
}
