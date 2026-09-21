param(
    [switch]$Scan,
    [switch]$Clean,
    [switch]$All,
    [switch]$DryRun,
    [switch]$Schedule,
    [switch]$RemoveSchedule,
    [switch]$Startup,
    [switch]$RemoveStartup,
    [switch]$StartupClean
)

$ErrorActionPreference = "Continue"
$ScriptDir = $PSScriptRoot
if ([string]::IsNullOrEmpty($ScriptDir)) { $ScriptDir = (Get-Location).Path }
$LogFile = Join-Path $ScriptDir "SystemCleaner-windows.log"

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-Size {
    param([double]$Bytes)
    if ($Bytes -ge 1GB) { return ("{0:N2} GB" -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ("{0:N1} MB" -f ($Bytes / 1MB)) }
    return ("{0:N0} KB" -f ($Bytes / 1KB))
}

function Get-FolderStats {
    param([string]$Path)
    $result = @{ Count = 0; Bytes = 0.0 }
    if (-not (Test-Path -LiteralPath $Path)) { return $result }
    $files = Get-ChildItem -LiteralPath $Path -Recurse -Force -File -ErrorAction SilentlyContinue
    if ($files) {
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        $result.Count = $files.Count
        $result.Bytes = [double]$bytes
    }
    return $result
}

function Get-RecycleBinStats {
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.Namespace(10)
        $bytes = ($bin.Items() | Measure-Object -Property Size -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        $count = (($bin.Items() | Measure-Object).Count)
        if ($null -eq $count) { $count = 0 }
        return @{ Count = $count; Bytes = [double]$bytes }
    } catch {
        return @{ Count = 0; Bytes = 0.0 }
    }
}

function Remove-FolderContents {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    Get-ChildItem -LiteralPath $Path -Force -ErrorAction SilentlyContinue |
        Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
}

function Remove-RecycleBin {
    Clear-RecycleBin -DriveLetter $null -Force -ErrorAction SilentlyContinue
}

function Write-Log {
    param([string]$Message)
    $line = "[{0}] {1}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Message
    Add-Content -LiteralPath $LogFile -Value $line -ErrorAction SilentlyContinue
}

$categories = @()
$categories += @{
    Name = "User temp files"
    Desc = "Temporary files of your account (used by apps; safe to remove)"
    NeedsAdmin = $false
    GetStats = { Get-FolderStats $env:TEMP }
    Clean = { Remove-FolderContents $env:TEMP }
}
$categories += @{
    Name = "Windows temp files"
    Desc = "System temporary files (safe; emptied by Windows itself over time)"
    NeedsAdmin = $true
    GetStats = { Get-FolderStats "C:\Windows\Temp" }
    Clean = { Remove-FolderContents "C:\Windows\Temp" }
}
$categories += @{
    Name = "Recycle Bin"
    Desc = "Files you already deleted and confirmed"
    NeedsAdmin = $false
    GetStats = { Get-RecycleBinStats }
    Clean = { Remove-RecycleBin }
}
$browserCachePaths = @(
    "$env:LOCALAPPDATA\Google\Chrome\User Data",
    "$env:LOCALAPPDATA\Microsoft\Edge\User Data",
    "$env:LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
)
$categories += @{
    Name = "Browser caches"
    Desc = "Chrome/Edge/Brave cache files (pages reload a bit slower once; no logouts)"
    NeedsAdmin = $false
    GetStats = {
        $total = @{ Count = 0; Bytes = 0.0 }
        foreach ($base in $browserCachePaths) {
            if (Test-Path -LiteralPath $base) {
                Get-ChildItem -LiteralPath $base -Directory -Filter "*" -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -ne "Default" -or $_.Name -eq "Default" } |
                    ForEach-Object {
                        foreach ($sub in @("Cache", "Code Cache", "GPUCache")) {
                            $p = Join-Path $_.FullName $sub
                            if (Test-Path -LiteralPath $p) {
                                $s = Get-FolderStats $p
                                $total.Count += $s.Count
                                $total.Bytes += $s.Bytes
                            }
                        }
                    }
            }
        }
        return $total
    }
    Clean = {
        foreach ($base in $browserCachePaths) {
            if (Test-Path -LiteralPath $base) {
                Get-ChildItem -LiteralPath $base -Directory -Filter "*" -ErrorAction SilentlyContinue |
                    ForEach-Object {
                        foreach ($sub in @("Cache", "Code Cache", "GPUCache")) {
                            $p = Join-Path $_.FullName $sub
                            Remove-FolderContents $p
                        }
                    }
            }
        }
    }
}
$categories += @{
    Name = "Old cached thumbnails"
    Desc = "Picture thumbnail previews (Windows rebuilds them as needed)"
    NeedsAdmin = $false
    GetStats = {
        $p = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        $files = Get-ChildItem -LiteralPath $p -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "thumbcache_*" -or $_.Name -like "iconcache_*" }
        $bytes = ($files | Measure-Object -Property Length -Sum).Sum
        if ($null -eq $bytes) { $bytes = 0 }
        return @{ Count = if ($files) { $files.Count } else { 0 }; Bytes = [double]$bytes }
    }
    Clean = {
        $p = "$env:LOCALAPPDATA\Microsoft\Windows\Explorer"
        Get-ChildItem -LiteralPath $p -Force -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -like "thumbcache_*" -or $_.Name -like "iconcache_*" } |
            Remove-Item -Force -ErrorAction SilentlyContinue
    }
}
$categories += @{
    Name = "Windows Update cache"
    Desc = "Downloaded update installers already installed (safe to purge)"
    NeedsAdmin = $true
    GetStats = { Get-FolderStats "C:\Windows\SoftwareDistribution\Download" }
    Clean = { Remove-FolderContents "C:\Windows\SoftwareDistribution\Download" }
}

function Show-Scan {
    param([string]$Title)
    Write-Host ""
    Write-Host "===== SystemCleaner - $Title =====" -ForegroundColor Cyan
    $grand = 0.0
    $i = 1
    foreach ($c in $categories) {
        $r = & $c.GetStats
        $grand += $r.Bytes
        $tag = ""
        if ($c.NeedsAdmin -and -not (Test-Admin)) { $tag = "  (needs admin - run as administrator to clean)" }
        Write-Host ("{0,2}. {1,-28} {2,10}  {3,8} files{4}" -f $i, $c.Name, (Format-Size $r.Bytes), $r.Count, $tag)
        Write-Host ("     {0}" -f $c.Desc) -ForegroundColor DarkGray
        $i++
    }
    Write-Host ""
    Write-Host ("TOTAL recoverable: {0}" -f (Format-Size $grand)) -ForegroundColor Yellow
    Write-Host ""
}

function Invoke-CleanCategory {
    param($Category)
    $before = & $Category.GetStats
    & $Category.Clean
    Start-Sleep -Milliseconds 200
    $after = & $Category.GetStats
    $freed = $before.Bytes - $after.Bytes
    if ($freed -lt 0) { $freed = 0 }
    Write-Host ("  cleaned {0}: freed {1}" -f $Category.Name, (Format-Size $freed)) -ForegroundColor Green
    Write-Log ("Cleaned '{0}' freed {1} ({2:N0} files)" -f $Category.Name, (Format-Size $freed), ($before.Count - $after.Count))
    return $freed
}

function Invoke-InteractiveClean {
    Show-Scan "select what to clean"
    Write-Host "Enter the numbers to clean, separated by commas." -ForegroundColor Yellow
    Write-Host "  'a' = all safe categories    'e' = exit" -ForegroundColor Yellow
    $choice = Read-Host "Choice"
    if ($choice -eq "e") { return }
    $indexes = @()
    if ($choice -eq "a") {
        $indexes = 1..$categories.Count
    } else {
        if ($choice -match "[\d\s,]+") {
            foreach ($n in ($choice -split ",")) {
                $n = $n.Trim()
                if ($n -match "^\d+$") {
                    $v = [int]$n
                    if ($v -ge 1 -and $v -le $categories.Count) { $indexes += $v }
                }
            }
        }
    }
    if ($indexes.Count -eq 0) {
        Write-Host "Nothing selected. Exiting." -ForegroundColor Yellow
        return
    }
    Write-Host ""
    Write-Host "Cleaning selected items..." -ForegroundColor Cyan
    $totalFreed = 0.0
    foreach ($idx in ($indexes | Sort-Object -Unique)) {
        $c = $categories[$idx - 1]
        if ($c.NeedsAdmin -and -not (Test-Admin)) {
            Write-Host ("  skipped '{0}': needs administrator rights" -f $c.Name) -ForegroundColor DarkYellow
            continue
        }
        $totalFreed += Invoke-CleanCategory $c
    }
    Write-Host ("Total freed: {0}" -f (Format-Size $totalFreed)) -ForegroundColor Green
}

function Set-Schedule {
    try {
        $trigger = New-ScheduledTaskTrigger -Daily -At 9am
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\clean-windows.ps1`" -Clean -All"
        $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable
        Unregister-ScheduledTask -TaskName "SystemCleaner Daily" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "SystemCleaner Daily" -Trigger $trigger -Action $action -Settings $settings -Description "Runs SystemCleaner every day at 09:00 (catches up if the PC was off)" -Force | Out-Null
        Write-Host "Scheduled task 'SystemCleaner Daily' created (runs every day at 09:00)." -ForegroundColor Green
        Write-Log "Scheduled daily 09:00 task created"
    } catch {
        Write-Host "Could not create the task. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-Schedule {
    $task = Get-ScheduledTask -TaskName "SystemCleaner Daily" -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName "SystemCleaner Daily" -Confirm:$false
        Write-Host "Scheduled task 'SystemCleaner Daily' removed." -ForegroundColor Green
        Write-Log "Scheduled task removed"
    } else {
        Write-Host "No scheduled task found (nothing to remove)." -ForegroundColor Yellow
    }
}

function Set-Startup {
    try {
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$ScriptDir\clean-windows.ps1`" -StartupClean"
        Unregister-ScheduledTask -TaskName "SystemCleaner Startup" -Confirm:$false -ErrorAction SilentlyContinue
        Register-ScheduledTask -TaskName "SystemCleaner Startup" -Trigger $trigger -Action $action -Description "SystemCleaner smart clean at logon (skips if already cleaned today)" -Force | Out-Null
        Write-Host "Startup clean enabled: runs when you log in, only if today's clean hasn't run yet." -ForegroundColor Green
        Write-Log "Startup clean enabled"
    } catch {
        Write-Host "Could not enable startup clean. Error: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Remove-Startup {
    $task = Get-ScheduledTask -TaskName "SystemCleaner Startup" -ErrorAction SilentlyContinue
    if ($task) {
        Unregister-ScheduledTask -TaskName "SystemCleaner Startup" -Confirm:$false
        Write-Host "Startup clean disabled." -ForegroundColor Green
        Write-Log "Startup clean disabled"
    } else {
        Write-Host "Startup clean wasn't enabled (nothing to remove)." -ForegroundColor Yellow
    }
}

if ($Schedule) { Set-Schedule }
if ($RemoveSchedule) { Remove-Schedule }
if ($Startup) { Set-Startup }
if ($RemoveStartup) { Remove-Startup }

$isAdmin = Test-Admin

$cleanedToday = $false
$todayPattern = Get-Date -Format "yyyy-MM-dd"
if (Test-Path -LiteralPath $LogFile) {
    $cleanedToday = [bool](Select-String -LiteralPath $LogFile -Pattern $todayPattern -SimpleMatch -Quiet -ErrorAction SilentlyContinue)
}

if ($StartupClean) {
    if ($cleanedToday) {
        Write-Host "Startup check: already cleaned today. Skipping." -ForegroundColor DarkGray
    } else {
        Show-Scan "startup clean (today's clean hasn't run yet)"
        Write-Host "Cleaning all safe categories..." -ForegroundColor Cyan
        $totalFreed = 0.0
        foreach ($c in $categories) {
            if ($c.NeedsAdmin -and -not $isAdmin) {
                Write-Host ("  skipped '{0}': needs administrator rights" -f $c.Name) -ForegroundColor DarkYellow
                continue
            }
            $totalFreed += Invoke-CleanCategory $c
        }
        Write-Host ("Total freed: {0}" -f (Format-Size $totalFreed)) -ForegroundColor Green
        Write-Host ""
        Write-Host "Done. Log saved to: $LogFile" -ForegroundColor DarkGray
    }
} elseif ($Clean) {
    if ($DryRun) {
        Write-Host "DRY RUN: showing what WOULD be cleaned. Nothing deleted." -ForegroundColor Magenta
        Show-Scan "dry run"
    } elseif ($All) {
        Show-Scan "cleaning everything safe"
        Write-Host "Cleaning all safe categories..." -ForegroundColor Cyan
        $totalFreed = 0.0
        foreach ($c in $categories) {
            if ($c.NeedsAdmin -and -not $isAdmin) {
                Write-Host ("  skipped '{0}': needs administrator rights" -f $c.Name) -ForegroundColor DarkYellow
                continue
            }
            $totalFreed += Invoke-CleanCategory $c
        }
        Write-Host ("Total freed: {0}" -f (Format-Size $totalFreed)) -ForegroundColor Green
        Write-Host ""
        Write-Host "Done. Log saved to: $LogFile" -ForegroundColor DarkGray
    } else {
        Invoke-InteractiveClean
    }
} else {
    if (-not $Schedule -and -not $RemoveSchedule -and -not $Startup -and -not $RemoveStartup) {
        Show-Scan "scan report (nothing was deleted)"
        Write-Host "To clean:  .\clean-windows.ps1 -Clean          (pick items)"
        Write-Host "To clean all safe items: .\clean-windows.ps1 -Clean -All"
        Write-Host "To preview only:          .\clean-windows.ps1 -Clean -All -DryRun"
        Write-Host "To auto-run daily:        .\clean-windows.ps1 -Schedule"
        Write-Host "To stop auto-run:         .\clean-windows.ps1 -RemoveSchedule"
        Write-Host "To clean at startup:      .\clean-windows.ps1 -Startup"
        Write-Host "To stop startup clean:    .\clean-windows.ps1 -RemoveStartup"
        Write-Host ""
        Write-Host "Log file: $LogFile"
    }
}