param(
    [string]$ServerDir = "",
    [int]$Port = 8085,
    [switch]$ProgressOnly
)

if (-not $ServerDir) {
    $ServerDir = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "server"
}

$logPath = Join-Path $ServerDir "Server.log"
$status = "loading"
$tailText = ""

if (Test-Path -LiteralPath $logPath) {
    try {
        $stream = [System.IO.File]::Open($logPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
        try {
            $reader = New-Object System.IO.StreamReader($stream)
            $all = $reader.ReadToEnd()
            $reader.Close()
            if ($all.Length -gt 8000) { $tailText = $all.Substring($all.Length - 8000) } else { $tailText = $all }
        } finally {
            $stream.Close()
        }
    } catch {
        $tailText = (Get-Content -LiteralPath $logPath -Tail 40 -ErrorAction SilentlyContinue) -join "`n"
    }

    if ($tailText -match "worldserver-daemon\) ready") { $status = "ready" }
    elseif ($tailText -match "World initialized") { $status = "initialized" }
}

if ($status -eq "ready") {
    if ($ProgressOnly) { Write-Output $status; exit 0 }
    Write-Output "log"
    exit 0
}

try {
    $listeners = @(Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue)
    if ($listeners.Count -gt 0) {
        if ($ProgressOnly) { Write-Output "ready"; exit 0 }
        Write-Output "port"
        exit 0
    }
} catch { }

$netstat = netstat -ano 2>$null | Select-String ":$Port" | Select-String "LISTENING"
if ($netstat) {
    if ($ProgressOnly) { Write-Output "ready"; exit 0 }
    Write-Output "port"
    exit 0
}

if ($ProgressOnly) {
    Write-Output $status
    exit 1
}

if ($status -eq "initialized") {
    Write-Output "log-partial"
    exit 1
}

exit 1
