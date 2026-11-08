# Shared package availability checks for alias generators
{ pkgs }:
{
  hasRg = pkgs ? ripgrep;
  hasNmap = pkgs ? nmap;
  hasCurl = pkgs ? curl;
  hasJq = pkgs ? jq;
  hasUg = pkgs ? ugrep;
  hasErd = pkgs ? erdtree;
  hasDuf = pkgs ? duf;
  hasDust = pkgs ? dust;
  hasHandlr = pkgs ? handlr;
  hasWget2 = pkgs ? wget2;
  hasPlocate = pkgs ? plocate;
  hasOuch = pkgs ? ouch;
  hasPigz = pkgs ? pigz;
  hasPbzip2 = pkgs ? pbzip2;
  hasHxd = pkgs ? hexyl || pkgs ? hxd;
  hasMpvc = pkgs ? mpvc;
  hasMpv = pkgs ? mpv;
  hasRlwrap = pkgs ? rlwrap;
  hasYtDlp = pkgs ? yt-dlp;
  hasKhal = pkgs ? khal;
  # nixpkgs renamed the package to `bottom`; the binary is still `btm`.
  hasBtm = pkgs ? bottom;
  hasIotop = pkgs ? iotop;
  hasLsof = pkgs ? lsof;
  hasFd = pkgs ? fd;
  hasMpc = pkgs ? mpc;
}
