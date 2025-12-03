##
# Module: system/net/proxy
# Purpose: V2Ray/V2RayA proxy utilities.
# Key options: none.
# Dependencies: pkgs.
{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.sing-box # proxy core supporting VLESS/Reality and tun
    pkgs.xray # VLESS/Reality-capable proxy core
  ];
}
