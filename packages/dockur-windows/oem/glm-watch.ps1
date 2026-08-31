# glm-watch.ps1 — keep Genelec GLM connected to the GLM adapter inside the VM.
# Starts GLM only AFTER the adapter is present, and restarts GLM whenever the
# adapter (re)appears: QEMU usb-host passthrough cycles can attach it late or
# re-attach it while GLM is already running, leaving the monitors OFFLINE.
$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\glm-watch.log'
$glmExe = 'C:\Program Files (x86)\Genelec\GLMv5\GLMv5.exe'

function Log($m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $m) }

function Test-Adapter {
  [bool](Get-PnpDevice -PresentOnly -ErrorAction SilentlyContinue |
    Where-Object { $_.InstanceId -match 'VID_1781' -and $_.InstanceId -match 'PID_0E39' })
}
function Test-Glm { [bool](Get-Process -Name 'GLMv5' -ErrorAction SilentlyContinue) }
function Restart-Glm {
  Log 'restarting GLM (adapter state changed)'
  Get-Process -Name 'GLMv5' -ErrorAction SilentlyContinue | Stop-Process -Force
  Start-Sleep -Seconds 3
  Start-Process -FilePath $glmExe
  Log 'GLM started'
}

# Phase 1: wait for the adapter (up to 120s), then ensure GLM runs after it.
Log 'glm-watch started'
$deadline = (Get-Date).AddSeconds(120)
while (-not (Test-Adapter) -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
if (Test-Adapter) {
  Log 'adapter present'
  if (Test-Glm) { Restart-Glm } else { Start-Process -FilePath $glmExe; Log 'GLM started' }
} else {
  Log 'adapter not found within 120s — starting GLM anyway'
  if (-not (Test-Glm)) { Start-Process -FilePath $glmExe; Log 'GLM started' }
}

# Phase 2: poll every 5s; restart GLM when the adapter (re)appears.
$had = Test-Adapter
while ($true) {
  Start-Sleep -Seconds 5
  $now = Test-Adapter
  if ($now -and -not $had) {
    Start-Sleep -Seconds 5
    Restart-Glm
  }
  $had = $now
}
