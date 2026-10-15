# proxy-sync.ps1 - keep the per-user WinINET proxy in sync with the machine value.
#
# setup.ps1 seeds HKLM (and the Default profile) once, at provisioning time. WinINET reads HKCU
# before HKLM, and each user hive is a copy made at first logon - so after the host uplink moves
# to another LAN the machine values follow the repo while every existing hive keeps the old alias
# (seen 2026-10-15: OneDrive in SYN-SENT to the retired 192.168.2.88:10812).
#
# This script copies ProxyEnable/ProxyServer from HKLM into HKCU and every loaded S-1-5-21-* hive,
# then asks WinINET to re-read the settings. setup.ps1 registers it as the logon hook GLMProxySync;
# after a LAN move run it once with the new alias (it also writes HKLM):
#
#   powershell -ExecutionPolicy Bypass -File C:\OEM\proxy-sync.ps1 -Proxy 192.168.0.11:10812
param(
    [string]$Proxy = '',
    [switch]$InstallHook
)

$ErrorActionPreference = 'SilentlyContinue'
$log = 'C:\OEM\proxy-sync.log'
function Log($m) {
    Add-Content -Path $log -Value ("[{0}] {1}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $m) -Encoding UTF8
}

$machine = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$userPath = '\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

if ($InstallHook) {
    $run = 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run'
    $cmd = 'powershell -NoLogo -NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\OEM\proxy-sync.ps1'
    Set-ItemProperty -Path $run -Name GLMProxySync -Value $cmd -Type String
    Log 'logon hook registered (HKLM Run: GLMProxySync)'
}

if ($Proxy) {
    Set-ItemProperty -Path $machine -Name ProxyEnable -Value 1 -Type DWord
    Set-ItemProperty -Path $machine -Name ProxyServer -Value $Proxy -Type String
    Log ('machine proxy set to ' + $Proxy)
}

$mp = Get-ItemProperty -Path $machine
$want = $mp.ProxyServer
$wantEnable = $mp.ProxyEnable
if (-not $want) {
    Log 'no machine ProxyServer value - nothing to sync'
    exit 0
}

$targets = @('HKCU:' + $userPath)
Get-ChildItem 'Registry::HKEY_USERS' | Where-Object { $_.PSChildName -match '^S-1-5-21' } | ForEach-Object {
    $targets += 'Registry::HKEY_USERS\' + $_.PSChildName + $userPath
}

$changed = @()
foreach ($key in $targets) {
    $cur = Get-ItemProperty -Path $key
    if ($null -eq $cur) { continue }
    if ($cur.ProxyServer -eq $want -and $cur.ProxyEnable -eq $wantEnable) { continue }
    Set-ItemProperty -Path $key -Name ProxyEnable -Value $wantEnable -Type DWord
    Set-ItemProperty -Path $key -Name ProxyServer -Value $want -Type String
    $changed += $key
}

if ($changed.Count -gt 0) {
    Log ('synced -> ' + $want + ' : ' + ($changed -join '; '))
    try {
        if (-not ('Win32.Inet' -as [type])) {
            Add-Type -Namespace Win32 -Name Inet -MemberDefinition '[DllImport("wininet.dll", SetLastError=true)] public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);'
        }
        [Win32.Inet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0) | Out-Null
        [Win32.Inet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0) | Out-Null
        Log 'wininet settings refreshed'
    } catch {
        Log ('wininet refresh failed: ' + $_.Exception.Message)
    }
} else {
    Log ('user hives already in sync (' + $want + ')')
}
