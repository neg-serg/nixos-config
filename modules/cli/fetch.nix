{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.cpufetch # CPU info fetch
    pkgs.fastfetch # modern ASCII system summary
    pkgs.ramfetch # RAM info fetch
  ];
}
