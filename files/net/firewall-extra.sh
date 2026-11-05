iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 10810 -j nixos-fw-accept

# LocalSend (53317/tcp+udp). Receiving has to work on *any* LAN — a phone
# hotspot, a friend's Wi-Fi, the venue network — so the port cannot live in
# interfaces.net1 (policy.nix), and it must not join the global lists either,
# which policy.nix clears on purpose. Accepting from private sources on every
# interface is "any LAN, never the internet"; outbound (sending files) needs no
# rule at all, because the stateful RELATED,ESTABLISHED accept covers replies.
iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 53317 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 53317 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 53317 -j nixos-fw-accept
iptables -A nixos-fw -s 10.0.0.0/8 -p udp --dport 53317 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p udp --dport 53317 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p udp --dport 53317 -j nixos-fw-accept
