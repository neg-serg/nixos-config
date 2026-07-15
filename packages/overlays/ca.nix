# Content-addressed derivations — disabled for now.
# To add a package, uncomment and add entries:
#   { vivaldi = ca prev.vivaldi; }
_: _: prev:
let
  ca =
    drv:
    if drv ? overrideAttrs then
      drv.overrideAttrs (_: {
        __contentAddressed = true;
      })
    else
      drv;
in
{ }
