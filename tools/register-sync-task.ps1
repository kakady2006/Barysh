# Registers BaryshSync to start at Windows logon (Task Scheduler), without a console window.
# Usage: powershell -ExecutionPolicy Bypass -File tools\register-sync-task.ps1
#        powershell -ExecutionPolicy Bypass -File tools\register-sync-task.ps1 -Remove
param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$name = 'BaryshSync'

if ($Remove) {
    Unregister-ScheduledTask -TaskName $name -Confirm:$false
    Write-Host "Removed task $name"
    return
}

$script = Join-Path $PSScriptRoot '..\sync\run.pyw' | Resolve-Path
$pythonw = (Get-Command pythonw -ErrorAction Stop).Source

$action = New-ScheduledTaskAction -Execute $pythonw -Argument "`"$script`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
    -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Force | Out-Null
Write-Host "Registered task $name -> $pythonw $script"
Write-Host "Start now: Start-ScheduledTask -TaskName $name"
