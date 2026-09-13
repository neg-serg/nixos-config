iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 10810 -j nixos-fw-accept
# 10811: auth-less SOCKS for the dockur Windows VM (in-lan-vm inbound,
# host alias 192.168.2.88) — same private-range restriction as 10810.
iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 10811 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 10811 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 10811 -j nixos-fw-accept
# 10812: auth-less HTTP CONNECT for the Windows VM system proxy
# (WinINET doesn't support SOCKS; GLM and other GUI apps use WinINET).
iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 10812 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 10812 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 10812 -j nixos-fw-accept
# 9003: glm-midi-relay TCP listener — the VM's MIDI bridge connects OUT
# to 192.168.2.88:9003 (VM-initiated TCP is the only bidirectional
# host<->VM channel under the same-IP pasta topology; RTP-MIDI UDP
# replies to the VM's own address get lost).
iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 9003 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 9003 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 9003 -j nixos-fw-accept
# 5010/5011: RTP-MIDI listener (rtpmidid, data+control) — the Windows
# VM's rtpMIDI connects OUT to 192.168.2.88:5010 (host alias; the .87
# address is the VM's own). 5011 = control port, required for handshake.
iptables -A nixos-fw -s 10.0.0.0/8 -p udp --dport 5010 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p udp --dport 5010 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p udp --dport 5010 -j nixos-fw-accept
iptables -A nixos-fw -s 10.0.0.0/8 -p udp --dport 5011 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p udp --dport 5011 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p udp --dport 5011 -j nixos-fw-accept
