{ mkBool, ... }:
{
  options.features.apps = {
    throne.enable = mkBool "enable Throne GUI proxy configuration manager" false;
  };
}
