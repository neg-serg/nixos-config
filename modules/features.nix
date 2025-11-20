{
  lib,
  config,
  inputs,
  ...
} @ args:
with lib; let
  hmFeatures = import (inputs.self + "/home/modules/features.nix") args;
in {
  options = hmFeatures.options;
  config = hmFeatures.config;
}
