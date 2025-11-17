{
  # Only allow specific unfree packages by name (synced with Home Manager)
  allowUnfreePredicate = pkg: let
    name = (pkg.pname or (builtins.parseDrvName (pkg.name or "")).name);
    allowed = @ALLOWED@;
  in builtins.elem name allowed;
}
