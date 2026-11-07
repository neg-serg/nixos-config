{ mkBool, ... }:
{
  options.features.apps = {
    obsidian = {
      # NB: only takes effect on hosts whose domain set includes "apps" — trantor
      # (trantorDomains) excludes that domain on purpose, so the flag is inert
      # there; the app is installed via flatpak instead.
      enable = mkBool "enable Obsidian knowledge base app + vault" false;
    };
    throne.enable = mkBool "enable Throne GUI proxy configuration manager" false;
  };
}
