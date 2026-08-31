param(
    [switch]$Clean,
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

Write-Output "Built Eloquence bridges under $Bin"
