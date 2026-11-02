iptables -A nixos-fw -s 10.0.0.0/8 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 172.16.0.0/12 -p tcp --dport 10810 -j nixos-fw-accept
iptables -A nixos-fw -s 192.168.0.0/16 -p tcp --dport 10810 -j nixos-fw-accept
