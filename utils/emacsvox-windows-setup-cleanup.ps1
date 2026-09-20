# Copyright (C) 2026 Emacsvox contributors
# SPDX-License-Identifier: GPL-2.0-or-later
# Dot-sourced only by the setup helper, after ownership and running-process checks.

function Get-CleanupTree([string]$Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return }
    $pending = New-Object 'Collections.Generic.Stack[string]'
    $pending.Push($Path)
    $count = 0
    while ($pending.Count) {
        $item = Get-Item -LiteralPath $pending.Pop() -Force
        if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw "Kept directory containing a junction or symbolic link: $($item.FullName)"
        }
        if (++$count -gt 100000) { throw "Too many files to review safely: $Path" }
        $item
        if ($item.PSIsContainer) {
            foreach ($child in Get-ChildItem -LiteralPath $item.FullName -Force) { $pending.Push($child.FullName) }
        }
    }
}

function Get-CleanupSize([string[]]$Names) {
    [long]$bytes = 0
    foreach ($name in $Names) {
        foreach ($item in @(Get-CleanupTree (Join-Path $InstallRoot $name))) {
            if (-not $item.PSIsContainer) { $bytes += $item.Length }
        }
    }
    return ('{0:N1} MB' -f ($bytes / 1MB))
}

function Remove-CleanupTree([string]$Name) {
    $path = Join-Path $InstallRoot $Name
    # Review the entire category before deleting anything. No recursive unlink
    # follows reparse points, including ones added after the initial review.
    $items = @(Get-CleanupTree $path)
    [long]$bytes = 0
    foreach ($item in ($items | Sort-Object { $_.FullName.Length } -Descending)) {
        $ancestor = $item.FullName
        while ($ancestor.Length -ge $path.Length) {
            $current = Get-Item -LiteralPath $ancestor -Force
            if ($current.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Cleanup path changed: $ancestor" }
            $ancestor = Split-Path $ancestor -Parent
        }
        if ($item.PSIsContainer) { [IO.Directory]::Delete($item.FullName, $false) }
        else { [IO.File]::Delete($item.FullName); $bytes += $item.Length }
    }
    return "$Name removed: $('{0:N1}' -f ($bytes / 1MB)) MB."
}

function Get-VoiceCleanupRoot {
    if ($env:OMNIVOX_VOICE_ROOT) { return $env:OMNIVOX_VOICE_ROOT }
    return (Join-Path $env:LOCALAPPDATA 'Emacsvox\Omnivox\voices')
}

function Open-VoiceCleanupService {
    $current = [IO.File]::ReadAllText((Join-Path $InstallRoot 'current.json')) | ConvertFrom-Json
    if ($current.Product -ne $product -or $current.Build -notmatch '^\d{4}\.\d{1,2}\.\d+-dev-[a-f0-9]{16}$') {
        throw 'Cannot identify the installed Omnivox for voice cleanup.'
    }
    $manifest = Read-SetupManifest (Join-Path $InstallRoot "Manifests\$($current.Build).json")
    $files = @($manifest.Files | Where-Object { $_.Path -match '^Omnivox/[^/]+/omnivox[.]exe$' })
    if ($files.Count -ne 1) { throw 'Cannot identify a unique owned Omnivox executable.' }
    $executable = Join-Path $InstallRoot $files[0].Path
    if ((Get-FileHash -LiteralPath $executable).Hash.ToLowerInvariant() -ne $files[0].SHA256) {
        throw 'The installed Omnivox changed. Downloaded voices have been kept.'
    }
    $start = New-Object Diagnostics.ProcessStartInfo
    $start.FileName = $executable
    $start.Arguments = '--voice-library-service'
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $process = New-Object Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw 'Could not open voice management.' }
    # Drain diagnostics to prevent a full stderr pipe from blocking replies.
    $script:VoiceCleanupErrors = $process.StandardError.ReadToEndAsync()
    return $process
}

function Invoke-VoiceCleanupRequest($Process, [hashtable]$Request) {
    $Request.request_id = ++$script:VoiceCleanupRequestId
    $Process.StandardInput.WriteLine(($Request | ConvertTo-Json -Compress -Depth 20))
    $Process.StandardInput.Flush()
    $task = $Process.StandardOutput.ReadLineAsync()
    if (-not $task.Wait(15000)) { throw 'Voice management timed out. Unconfirmed files have been kept.' }
    $line = $task.Result
    if (-not $line -or -not $line.StartsWith('OMNIVOX-LOCAL ') -or $line.Length -gt 4194304) {
        throw 'Voice management returned no valid reply.'
    }
    $reply = $line.Substring(14) | ConvertFrom-Json
    if ($reply.request_id -ne $Request.request_id) { throw 'Voice management reply did not match the request.' }
    if ($reply.type -eq 'error') { throw $reply.message }
    return $reply
}

function Invoke-VoiceCleanup([bool]$Remove) {
    $root = Get-VoiceCleanupRoot
    if (-not (Test-Path -LiteralPath (Join-Path $root 'host.json'))) { return 'No managed downloaded voice library found.' }
    $process = $null
    $script:VoiceCleanupRequestId = 0
    try {
        $process = Open-VoiceCleanupService
        $hostInfo = Invoke-VoiceCleanupRequest $process @{ command='host' }
        if ($hostInfo.removal_version -ne 1) { throw 'This Omnivox does not support reviewed voice removal.' }
        $library = Invoke-VoiceCleanupRequest $process @{ command='inspect' }
        $packages = @($library.index.packages | Where-Object { $_.ownership -eq 'managed' })
        [long]$bytes = 0
        foreach ($package in $packages) { foreach ($file in $package.files) { $bytes += $file.bytes } }
        "Shared downloaded voices: $($packages.Count) packages, $('{0:N1}' -f ($bytes / 1MB)) MB installed."
        "Library: $($hostInfo.root)"
        if (-not $Remove) { return }
        foreach ($package in $packages) {
            # Refresh the index hash after each successful removal. The native
            # service rechecks all profiles, live sessions and activation leases.
            $library = Invoke-VoiceCleanupRequest $process @{ command='inspect' }
            $rows = @($library.index.voices | Where-Object {
                $_.package_id -eq $package.package_id -and $_.revision_id -eq $package.revision_id
            })
            if (-not $rows.Count) { continue }
            $name = $rows[0].display_name
            try {
                $review = (Invoke-VoiceCleanupRequest $process @{
                    command='uninstall-preview'; engine=$rows[0].engine_id; voice=$rows[0].physical_id;
                    expected_sha256=$library.sha256
                }).review
                if (@($review.blockers).Count) { "Kept ${name}: $($review.blockers -join '; ')"; continue }
                $result = (Invoke-VoiceCleanupRequest $process @{
                    command='uninstall'; operation=$review.operation_id; expected_sha256=$review.plan_sha256
                }).result
                "${name}: $($result.status); $($result.removed_bytes) bytes removed, $($result.remaining_bytes) bytes retained. $($result.detail)"
            }
            catch { "Kept ${name}: $($_.Exception.Message)" }
        }
    }
    finally {
        if ($process) {
            if (-not $process.HasExited) {
                $process.StandardInput.Close()
                if (-not $process.WaitForExit(2000)) { $process.Kill(); $process.WaitForExit() }
            }
            $process.Dispose()
        }
    }
}

function Invoke-SetupCleanup {
    $owner = Join-Path $InstallRoot 'setup-owner.json'
    if (([IO.File]::ReadAllText($owner) | ConvertFrom-Json).Product -ne $product) {
        throw 'Personal-data cleanup requires this installation ownership marker.'
    }
    $lines = New-Object 'Collections.Generic.List[string]'
    if ($Action -eq 'CleanupReview') {
        $lines.Add('Personal data is kept unless you select it below.')
        $lines.Add("Installation: $InstallRoot")
        foreach ($category in @(@('logs','Cache'), @('profile'))) {
            try { $lines.Add("$($category -join ' and '): $(Get-CleanupSize $category)") }
            catch { $lines.Add($_.Exception.Message) }
        }
        try { foreach ($line in @(Invoke-VoiceCleanup $false)) { $lines.Add($line) } }
        catch { $lines.Add("Downloaded voices could not be inspected: $($_.Exception.Message)") }
        $lines.Add('The profile choice removes files inside this installation profile only. Shared Emacsvox palettes and settings outside it are kept.')
        $lines.Add('Voice cleanup affects the shared Omnivox library. Only managed, unreferenced packages can be removed. Active, shared, imported and system voices are kept.')
        $lines.Add('To remove active downloads, disable them and Apply in Browse voices before uninstalling. Close other speech sessions using those voices.')
    }
    else {
        if ($RemoveVoices) {
            try { foreach ($line in @(Invoke-VoiceCleanup $true)) { $lines.Add($line) } }
            catch { $lines.Add("Voice cleanup incomplete: $($_.Exception.Message)") }
        }
        $names = @()
        if ($RemoveProfile) { $names += 'profile' }
        if ($RemoveLogs) { $names += 'logs'; $names += 'Cache' }
        foreach ($name in $names) {
            try { $lines.Add((Remove-CleanupTree $name)) }
            catch { $lines.Add("Cleanup incomplete for ${name}: $($_.Exception.Message)") }
        }
        if (-not $lines.Count) { $lines.Add('Your profile, logs, cache and downloaded voices have been kept.') }
    }
    [IO.File]::WriteAllLines($ResultFile, $lines, (New-Object Text.UTF8Encoding($false)))
}
