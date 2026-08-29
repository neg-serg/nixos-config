# dockur OEM provisioning — runs during Windows setup as SYSTEM.
# Proxy (machine-wide) + optional silent installers from C:\OEM\installers\.
$ErrorActionPreference = 'Continue'
$log = 'C:\OEM\setup.log'
function Log($m) { Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8 }

Log "setup.ps1 start"

# --- 1. WinINET system proxy (machine-wide; GLM and other GUI apps) ---
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f | Out-Null
reg add "HKLM\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "192.168.2.88:10812" /f | Out-Null
# WinINET/.NET reads HKCU first: pre-seed the Default user profile so the
# first-logon user (neg) gets the proxy in HKCU automatically.
reg load "HKU\Default" "C:\Users\Default\NTUSER.DAT" | Out-Null
if ($LASTEXITCODE -eq 0) {
  reg add "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyEnable /t REG_DWORD /d 1 /f | Out-Null
  reg add "HKU\Default\Software\Microsoft\Windows\CurrentVersion\Internet Settings" /v ProxyServer /t REG_SZ /d "192.168.2.88:10812" /f | Out-Null
  reg unload "HKU\Default" | Out-Null
}
Log "WinINET proxy set (192.168.2.88:10812, HKLM + Default profile)"

# --- 2. Edge policy proxy (fixed_servers, SOCKS — Chromium cannot auth SOCKS) ---
reg add "HKLM\Software\Policies\Microsoft\Edge" /v ProxyMode /t REG_SZ /d fixed_servers /f | Out-Null
reg add "HKLM\Software\Policies\Microsoft\Edge" /v ProxyServer /t REG_SZ /d "socks5://192.168.2.88:10811" /f | Out-Null
Log "Edge policy proxy set (socks5://192.168.2.88:10811)"

# --- 3. Environment variables (machine-wide, for new console processes) ---
setx /M ALL_PROXY "socks5h://192.168.2.88:10811" | Out-Null
setx /M HTTPS_PROXY "socks5h://192.168.2.88:10811" | Out-Null
setx /M HTTP_PROXY "socks5h://192.168.2.88:10811" | Out-Null
Log "env proxy vars set"

# --- 4. Silent installers from C:\OEM\installers\ (drop your .exe/.msi there) ---
$instDir = 'C:\OEM\installers'
if (Test-Path $instDir) {
  Get-ChildItem $instDir -File | Where-Object { $_.Extension -in '.exe', '.msi' } | ForEach-Object {
    $f = $_.FullName
    Log ("installing: " + $_.Name)
    $argsList = @()
    # common silent flags: NSIS /S, Inno /VERYSILENT, MSI /qn
    if ($_.Extension -eq '.msi') { $argsList = @('/qn', '/norestart') }
    elseif ($_.Extension -eq '.exe') {
      $argsList = @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART')
      # try NSIS /S first if Inno flags are unsupported? attempt Inno then fallback
    }
    try {
      $p = Start-Process -FilePath $f -ArgumentList $argsList -Wait -PassThru
      Log ("  exit code: " + $p.ExitCode)
    } catch {
      Log ("  install failed: " + $_.Exception.Message)
      # fallback: try NSIS /S
      try {
        $p = Start-Process -FilePath $f -ArgumentList @('/S') -Wait -PassThru
        Log ("  retry /S exit code: " + $p.ExitCode)
      } catch { Log ("  retry failed: " + $_.Exception.Message) }
    }
  }
} else {
  Log "no installers dir"
}

Set-Content -Path 'C:\OEM\provisioned.txt' -Value ("provisioned {0}" -f (Get-Date)) -Encoding UTF8
Log "setup.ps1 done"
