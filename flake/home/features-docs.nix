{lib}: let
  toList = optSet: prefix:
    lib.concatLists (
      lib.mapAttrsToList (
        name: v: let
          cur = lib.optionalString (prefix != "") (prefix + ".") + name;
        in
          if (v ? _type) && (v._type == "option")
          then [
            {
              path = cur;
              description = v.description or "";
              desc = v.description or "";
              type =
                if (v ? type) && (v.type ? name)
                then v.type.name
                else (v.type.description or "unknown");
              default = v.default or null;
              defaultText = v.defaultText or null;
              def =
                v.defaultText or (
                  if v ? default
                  then builtins.toJSON v.default
                  else ""
                );
            }
          ]
          else if builtins.isAttrs v
          then toList v cur
          else []
      )
      optSet
    );
in rec {
  # Evaluate module-provided feature options and return a flat list
  getFeatureOptionsItems = {
    module,
    specialArgs ? {},
  }: let
    eval = lib.evalModules {
      inherit specialArgs;
      modules = [
        ({lib, ...}: {
          config._module.check = false; # silence deprecation: pass via module instead of evalModules.check
          config.lib.neg.mkBool = desc: default: (lib.mkEnableOption desc) // {inherit default;};
        })
        module
        ({lib, ...}: {
          options.assertions = lib.mkOption {
            type = lib.types.anything;
            visible = false;
            description = "internal";
          };
        })
      ];
    };
    opts = eval.options;
    items = toList opts "";
  in
    lib.filter (o: !(lib.hasPrefix "assertions" o.path)) items;

  # Merge feature option listings, preferring system-defined entries on conflicts
  mergeFeatureItems = {home, system}: let
    toAttr = items:
      lib.listToAttrs (map (o: {
          name = o.path;
          value = o;
        })
        items);
    homeMap = toAttr home;
    systemMap = toAttr system;
    combined = homeMap // systemMap;
    ordered = lib.sort (a: b: a < b) (builtins.attrNames combined);
  in
    map (name: combined.${name}) ordered;

  renderFeaturesOptionsMd = items: let
    esc = s: lib.replaceStrings ["\n" "|"] [" " "\\|"] (toString s);
    rows = lib.concatStringsSep "\n" (map (o: "| ${o.path} | " + esc o.type + " | " + esc o.def + " | " + esc o.desc + " |") items);
  in ''
    # Features Options (auto-generated)

    | Option | Type | Default | Description |
    |---|---|---|---|
    ${rows}
  '';

  renderFeaturesOptionsJson = items: builtins.toJSON items;

}
