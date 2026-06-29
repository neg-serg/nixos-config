# repo.or.cz generates non-reproducible tarballs for tinycc snapshots.
# Use GitHub mirror instead, with the same patches as upstream mes.nix.
inputs: final: prev:
let
  inherit (final) lib stdenv;

  rev = "cb41cbfe717e4c00d7bb70035cda5ee5f0ff9341";

  makeMesSrc =
    { patches ? "" }:
    stdenv.mkDerivation {
      name = "tinycc-mes-source";
      src = final.fetchurl {
        url = "https://github.com/TinyCC/tinycc/archive/${rev}.tar.gz";
        hash = "sha256-c4H5RKqSVc1WDoGSxbAkEkbSyD7qVLjrMXECmS/h4rs=";
      };
      sourceRoot = "tinycc-${rev}";
      dontBuild = true;
      installPhase = ''
        mkdir -p $out
        cp -r . $out/
      '';
      postPatch = patches;
    };

  mesPatches = ''
    substituteInPlace libtcc.c \
      --replace-fail "s->ms_extensions = 1;" "s->ms_extensions = 1; s->static_link = 1;"
    substituteInPlace i386-asm.c \
      --replace-fail "switch(size)" "if (reg >= 8) { cstr_printf(add_str, \"%%r%d%c\", reg, (size == 1) ? 'b' : ((size == 2) ? 'w' : ((size == 4) ? 'd' : ' '))); return; } switch(size)"
    substituteInPlace tccgen.c \
      --replace-fail "vpush_type_size(pointed_type(&vtop[-1].type), &align);" "vpush_type_size(pointed_type(&vtop[-1].type), &align); if (!(vtop[-1].type.t & VT_UNSIGNED)) gen_cast_s(VT_PTRDIFF_T);"
  '';

in
{
  minimal-bootstrap = prev.minimal-bootstrap.overrideScope (self: super: {
    tinycc-mes = super.tinycc-mes.overrideAttrs (_old: {
      src = makeMesSrc { patches = mesPatches; };
    });
    tinycc-musl = super.tinycc-musl.overrideAttrs (_old: {
      src = makeMesSrc { patches = ""; };
    });
    tinycc-musl-intermediate = super.tinycc-musl-intermediate.overrideAttrs (_old: {
      src = makeMesSrc { patches = ""; };
    });
  });
}
