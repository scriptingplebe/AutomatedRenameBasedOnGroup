# Retrieves the entra device ID from the local machine
$AzureAdDeviceId = (dsregcmd /status |
    Select-String "DeviceId\s+:" |
    Select-Object -First 1 |
    ForEach-Object { $_.ToString().Split(":")[1].Trim() })
Write-Host "Entra Device ID: $AzureAdDeviceId"

# Grabs private certificate from the local machine's personal store
$Cert = Get-ChildItem Cert:\LocalMachine\My |
    Where-Object {
        $_.HasPrivateKey -and
        $_.Subject -eq "CN=$AzureAdDeviceId" -and
        $_.Issuer -like "# Your Issuer Cert"
    } |
    Select-Object -First 1
# Gets the device srial number
$Serial = (Get-CimInstance Win32_BIOS).SerialNumber

# Prepares the proxy URL and headers for the request
$ProxyUrl = "# Your url for your Azure Function"

$Headers = @{
    "Content-Type" = "application/json"
}
$Body = @{
    DeviceId     = $AzureAdDeviceId
    SerialNumber = $Serial
} | ConvertTo-Json

# Sends the request to the proxy to get the target name for the device
try {
    $Response = Invoke-RestMethod -Uri $ProxyUrl -Method "Post" -Certificate $Cert -ContentType "application/json" -Body $Body
} catch {
    Write-Error "Request failed: $($_.Exception.Message)"
    return
}

# Checks if a target name was returned from the proxy
if ($Response.TargetName) {
    Write-Output "Proxy assigned target name: $($Response.TargetName)"
} else {
    Write-Error "Failed to retrieve target name definition from the proxy."
}

# Checks if the target name is the same as the current computer name
If ($Response.TargetName -eq $env:COMPUTERNAME) {
    Exit 0
}

$NewComputerName = $Response.TargetName

$ScriptDirectory = "C:\ProgramData\Company\Scripts"
$ScriptPath      = Join-Path $ScriptDirectory "RenameComputer.ps1"

if (!(Test-Path $ScriptDirectory)) {
    New-Item -Path $ScriptDirectory -ItemType Directory -Force | Out-Null
}

$ScriptContent = @'
param(
    [Parameter(Mandatory = $true)]
    [string]# Your New Compuer Name
)
Rename-Computer -NewName # Your New Compuer Name -Force -ErrorAction Stop
Restart-Computer -Force
exit 0
'@

Set-Content -Path $ScriptPath -Value $ScriptContent -Encoding UTF8 -Force

$Action = New-ScheduledTaskAction `
    -Execute "powershell.exe" `
    -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" -NewComputerName `"# Your New Compuer Name`""

# Next 1:00 AM. If you run this before midnight, it's tomorrow at 1 AM.
$StartTime = (Get-Date).Date.AddDays(1).AddHours(1)

$Trigger = New-ScheduledTaskTrigger -Once -At $StartTime
$Trigger.EndBoundary = $StartTime.AddDays(1).ToString("yyyy-MM-ddTHH:mm:ss")

$Settings = New-ScheduledTaskSettingsSet `
    -StartWhenAvailable `
    -ExecutionTimeLimit (New-TimeSpan -Hours 1) `
    -DeleteExpiredTaskAfter (New-TimeSpan -Minutes 5)
# Register task
Register-ScheduledTask `
    -TaskName "RenameDesktop" `
    -Action $Action `
    -Trigger $Trigger `
    -Settings $Settings `
    -User SYSTEM `
    -RunLevel Highest `
    -Force

# Exits the script with a success code
Exit 0