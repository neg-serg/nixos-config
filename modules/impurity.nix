{
  self,
  inputs,
  ...
}: {
  imports = [inputs.impurity.nixosModules.impurity];

  impurity.configRoot = self;
  # Temporarily disabled - can be re-enabled by setting to true
  impurity.enable = false;
}
