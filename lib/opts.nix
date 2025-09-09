{ lib }:
let
  inherit (lib) types mkOption mkEnableOption concatStringsSep optional;

  # Build description/example/defaultText fields in a uniform way
  mkDoc = {
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    {
      description =
        if notes == null then description else concatStringsSep "\n" [ description notes ];
    }
    // (if example == null then {} else { inherit example; })
    // (if defaultText == null then {} else { inherit defaultText; });

  # Base option constructor
  mkOpt = type: default: docAttrs:
    mkOption ({ inherit type default; } // docAttrs);

  # Primitive helpers
  mkBoolOpt = {
    default ? false,
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    mkOpt types.bool default (mkDoc { inherit description notes example defaultText; });

  mkStrOpt = {
    default ? "",
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    mkOpt types.str default (mkDoc { inherit description notes example defaultText; });

  mkIntOpt = {
    default ? 0,
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    mkOpt types.int default (mkDoc { inherit description notes example defaultText; });

  mkPathOpt = {
    default ? null,
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
    nullable ? true,
  }:
    let
      t = if nullable then types.nullOr types.path else types.path;
      d = if default == null && !nullable then "" else default;
    in
      mkOpt t d (mkDoc { inherit description notes example defaultText; });

  # Higher-level helpers
  mkListOpt = elemType: {
    default ? [],
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    mkOpt (types.listOf elemType) default (mkDoc { inherit description notes example defaultText; });

  mkEnumOpt = values: {
    default ? null,
    description,
    notes ? null,
    example ? null,
    defaultText ? null,
  }:
    let
      def = if default == null then builtins.head values else default;
    in
      mkOpt (types.enum values) def (mkDoc { inherit description notes example defaultText; });
in {
  inherit
    mkDoc
    mkOpt
    mkBoolOpt
    mkStrOpt
    mkIntOpt
    mkPathOpt
    mkListOpt
    mkEnumOpt
    mkEnableOption;
}

