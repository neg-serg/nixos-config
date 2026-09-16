{ lib }:
let
  inherit (lib)
    types
    mkOption
    mkEnableOption
    concatStringsSep
    ;

  # Build description/example/defaultText fields in a uniform way
  mkDoc =
    {
      description,
      notes ? null,
      example ? null,
      defaultText ? null,
    }:
    {
      description =
        if notes == null then
          description
        else
          concatStringsSep "\n" [
            description
            notes
          ];
    }
    // lib.optionalAttrs (example != null) { inherit example; }
    // lib.optionalAttrs (defaultText != null) { inherit defaultText; };

  # Base option constructor
  mkOpt =
    type: default: docAttrs:
    mkOption ({ inherit type default; } // docAttrs);

  # The typed helpers all have one shape: a `{ default, description, notes,
  # example, defaultText }` record in, an option out. Only the type and the
  # fallback default differ, so they are one constructor plus five one-liners.
  mkTypedOpt =
    type: { default, ... }@args: mkOpt type default (mkDoc (builtins.removeAttrs args [ "default" ]));

  withDefault = fallback: args: { default = fallback; } // args;

  mkBoolOpt = args: mkTypedOpt types.bool (withDefault false args);

  mkStrOpt = args: mkTypedOpt types.str (withDefault "" args);

  mkIntOpt = args: mkTypedOpt types.int (withDefault 0 args);

  mkListOpt = elemType: args: mkTypedOpt (types.listOf elemType) (withDefault [ ] args);

  # An explicit `default = null` still means "the first enum value".
  mkEnumOpt =
    values: args:
    let
      chosen = if (args.default or null) == null then builtins.head values else args.default;
    in
    mkTypedOpt (types.enum values) (withDefault chosen (builtins.removeAttrs args [ "default" ]));
in
{
  inherit
    mkDoc
    mkOpt
    mkBoolOpt
    mkStrOpt
    mkIntOpt
    mkListOpt
    mkEnumOpt
    mkEnableOption
    ;
}
