{
  self,
  inputs,
  ...
}: {
  imports = [inputs.impurity.nixosModules.impurity];

  impurity.configRoot = self;
  impurity.enable = true;
}
