{
  allowAliases = false;
  permittedInsecurePackages = [
    "yandex-browser-stable-25.10.1.1173-1"
  ];
  rocmSupport = true;
  allowUnfreePredicate =
    pkg:
    let
      name = pkg.pname or (builtins.parseDrvName (pkg.name or "")).name;
      allowed = [
        "google-antigravity"
        "antigravity-fhs"
        "google-chrome"
        "yandex-browser-stable"
        "vivaldi"
        "beatprints"
        "richcolors"
        "steam-unwrapped"
        "steam"
        "steam-run"
      ];
    in
    builtins.elem name allowed;
}
