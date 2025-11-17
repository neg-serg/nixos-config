{
  lib,
  systems,
  perSystem,
  ...
}:
lib.genAttrs systems (
  s:
    perSystem.${s}.checks
)
