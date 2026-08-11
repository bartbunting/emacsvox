param(
    [switch]$Clean,
    [switch]$HelperOnly,
    [string]$OutputDirectory = "bin",
    [string]$CompilerPath,
    [string]$ReferenceDirectory
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

$CompilerArguments = @("/nologo")
if (![string]::IsNullOrEmpty($CompilerPath)) {
    if ([string]::IsNullOrEmpty($ReferenceDirectory)) {
        throw "ReferenceDirectory is required with CompilerPath"
    }
    $Compiler = $CompilerPath
    $CompilerArguments += @(
        "/deterministic+",
        "/debug-",
        "/nostdlib+",
        "/reference:$ReferenceDirectory\mscorlib.dll",
        "/reference:$ReferenceDirectory\System.dll",
        "/reference:$ReferenceDirectory\System.Core.dll",
        "/reference:$ReferenceDirectory\System.Web.Extensions.dll"
    )
} else {
    $Compiler = Join-Path $env:WINDIR `
        "Microsoft.NET\Framework64\v4.0.30319\csc.exe"
}
if (!(Test-Path $Compiler)) {
    throw "The C# compiler was not found at $Compiler"
}

New-Item -ItemType Directory -Force $Bin | Out-Null

& $Compiler @CompilerArguments /target:exe /optimize+ /platform:x86 `
    "/out:$Bin\OmnivoxEloquenceHelper32.exe" `
    (Join-Path $Root "OmnivoxEloquenceCapture.cs") `
    (Join-Path $Root "OmnivoxEloquenceHelper.cs") `
    (Join-Path $Common "OmnivoxHelperHost.cs")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build OmnivoxEloquenceHelper32.exe"
}

if (!$HelperOnly) {
    $BridgeSources = @(
        (Join-Path $Root "EloquenceBridge.cs"),
        (Join-Path $Common "BridgeProtocol.cs"),
        (Join-Path $Common "WaveOutPlayer.cs")
    )
    & $Compiler @CompilerArguments /target:exe /optimize+ /platform:x86 `
        "/out:$Bin\EloquenceBridge32.exe" $BridgeSources
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to build EloquenceBridge32.exe"
    }

    & $Compiler @CompilerArguments /target:exe /optimize+ /platform:x64 `
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
