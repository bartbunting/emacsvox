param(
    [switch]$Clean
)

$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Bin = Join-Path $Root "bin"

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
& $Compiler /nologo /target:exe /optimize+ /platform:x64 `
    "/out:$Bin\WindowsPlay.exe" `
    (Join-Path $Root "WindowsPlay.cs") `
    (Join-Path $Root "WaveOutClip.cs")
if ($LASTEXITCODE -ne 0) {
    throw "Failed to build WindowsPlay.exe"
}

Write-Output "Built $Bin\WindowsPlay.exe"
