# glm-midi-bridge.ps1 - one-way MIDI bridge for the dockur VM.
# Connects OUT to the host relay 192.168.2.88:9003 (TCP), receives raw MIDI
# messages (3 bytes: status CC value) and sends them to the rtpMIDI MIDI out
# port -> GLM software (Settings -> MIDI -> rtpMIDI port).
# The VM initiates the connection because host->VM UDP (RTP-MIDI) replies die
# on the same-IP pasta topology; outbound TCP works (like the .88:10812 proxy).
# Run:  powershell -ExecutionPolicy Bypass -File C:\OEM\glm-midi-bridge.ps1
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class GM {
  [DllImport("winmm.dll")] public static extern int midiOutOpen(out IntPtr h, uint id, IntPtr c, IntPtr w, uint f);
  [DllImport("winmm.dll")] public static extern int midiOutShortMsg(IntPtr h, uint m);
  [DllImport("winmm.dll")] public static extern int midiOutClose(IntPtr h);
  [DllImport("winmm.dll")] public static extern uint midiOutGetNumDevs();
  [DllImport("winmm.dll")] public static extern int midiOutGetDevCaps(uint id, IntPtr c, uint s);
}
"@

function Find-RtpMidiOut {
  $n = [GM]::midiOutGetNumDevs()
  for ($i = 0; $i -lt $n; $i++) {
    $c = [System.Runtime.InteropServices.Marshal]::AllocHGlobal(128)
    try {
      $rc = [GM]::midiOutGetDevCaps($i, $c, 128)
      if ($rc -eq 0) {
        $name = [System.Runtime.InteropServices.Marshal]::PtrToStringUni([IntPtr]::Add($c, 8), 32)
        if ($name -match 'loopMIDI|rtpMIDI') { return $i }
      }
    } finally {
      [System.Runtime.InteropServices.Marshal]::FreeHGlobal($c)
    }
  }
  return -1
}

$dev = Find-RtpMidiOut
if ($dev -lt 0) { Write-Host "rtpMIDI out device not found - is rtpMIDI installed?"; exit 1 }
$h = [IntPtr]::Zero
$rc = [GM]::midiOutOpen([ref]$h, $dev, [IntPtr]::Zero, [IntPtr]::Zero, 0)
if ($rc -ne 0) { Write-Host "midiOutOpen failed: $rc"; exit 1 }
Write-Host "bridge: host 192.168.2.88:9003 -> rtpMIDI device $dev (reconnecting...)"

while ($true) {
  $c = $null
  try {
    $c = New-Object System.Net.Sockets.TcpClient
    $c.Connect("192.168.2.88", 9003)
    $ns = $c.GetStream()
    Write-Host "bridge: connected to host relay"
    while ($true) {
      $buf = New-Object byte[] 3
      $have = 0
      while ($have -lt 3) {
        $n = $ns.Read($buf, $have, 3 - $have)
        if ($n -le 0) { break }
        $have += $n
      }
      if ($have -lt 3) { break }
      $msg = ([uint32]$buf[2] -shl 16) -bor ([uint32]$buf[1] -shl 8) -bor [uint32]$buf[0]
      [GM]::midiOutShortMsg($h, $msg) | Out-Null
    }
  } catch { }
  if ($c) { $c.Close() }
  Start-Sleep -Seconds 2
}
