# Shared builder for SuperCollider UGen plugin packages: a cmake build against
# the fake SC source root, plus the install layout scsynth and sclang actually
# read.
#
# Two invariants live here instead of in every plugin file:
#   - configure against `scPluginFarm` — the only tree that carries
#     include/plugin_interface, common/ and SCVersion.txt, which the old-style
#     SC cmake modules look for (the nixpkgs supercollider ships headers under
#     include/SuperCollider/) — and never for supernova, which the nixpkgs
#     engine does not build;
#   - upstream install trees are not the layout SC reads, so the server plugins
#     are hoisted to $out/lib/SuperCollider/plugins and the classes/help to
#     $out/share/SuperCollider/extensions/<installDir>. Without that copy the
#     plugin builds and then stays silent: scsynth never finds the .so and
#     sclang never finds the class files.
#
# Everything a plugin deviates with stays in the package file and is passed
# through untouched: vendored submodules (postUnpack), sed'd CMakeLists
# (preConfigure/postPatch), extra -D flags, buildInputs, env.
#
#   mkScPlugin {
#     pname = "xplaybuf"; version = "…";
#     src = fetchFromGitHub { … };
#     inherit scPluginFarm;
#     installDir = "XPlayBuf";
#     install = ''mv "$out/XPlayBuf"/*_scsynth.so "$pluginsDir/" …'';
#     meta = lib.mkMeta { … };
#   }
{
  lib,
  stdenv,
  cmake,
}:
{
  # pname / version / src (and every other mkDerivation attribute a plugin
  # passes: patches, postUnpack, preConfigure, postPatch, preBuild, buildInputs,
  # env, …) reach the derivation unchanged through `args` below, so they are not
  # listed here — the list is only what this builder owns.
  scPluginFarm,
  # Directory name under share/SuperCollider/extensions. SC resolves an
  # extension by the directory the .sc files sit in, so this is the name the
  # user types in sclang. null for the packages whose upstream install already
  # lands in the SC layout: nothing is created for them and the `install` body
  # only asserts the layout, so upstream drift still fails the build.
  installDir ? null,
  # Shell lines filling $pluginsDir/.so and $extdir/ — run from postInstall by
  # default, or as the install phase itself when upstream has no install rules.
  # Both variables exist only when installDir does.
  install,
  # false for packages whose CMakeLists installs nothing (the plugin .so stays
  # in the build directory): `install` then becomes the whole installPhase.
  upstreamInstalls ? true,
  # Extra -D… flags on top of the shared SC_PATH/SUPERNOVA pair.
  cmakeFlags ? [ ],
  meta,
  ...
}@args:
let
  # Both variables are exported by the install body below, so a package's own
  # lines only name what they move (`"$out/<Upstream>"`, `"$pluginsDir"`).
  dirs = lib.optionalString (installDir != null) ''
    pluginsDir="$out/lib/SuperCollider/plugins"
    extdir="$out/share/SuperCollider/extensions/${installDir}"
    mkdir -p "$pluginsDir" "$extdir"
  '';

  # Our own knobs never reach mkDerivation; everything else (patches,
  # postUnpack, preConfigure, postPatch, preBuild, buildInputs, env, …) is the
  # package's business and stays as written.
  packageAttrs = builtins.removeAttrs args [
    "scPluginFarm"
    "installDir"
    "install"
    "upstreamInstalls"
    "cmakeFlags"
    "meta"
  ];
in
stdenv.mkDerivation (
  packageAttrs
  // {
    nativeBuildInputs = [ cmake ] ++ (packageAttrs.nativeBuildInputs or [ ]);
    cmakeFlags = [
      "-DSC_PATH=${scPluginFarm}"
      "-DSUPERNOVA=OFF"
    ]
    ++ cmakeFlags;

    meta = {
      platforms = lib.platforms.all;
      maintainers = [ ];
    }
    // meta;
  }
  // lib.optionalAttrs upstreamInstalls {
    postInstall = ''
      ${dirs}
      ${install}
    '';
  }
  // lib.optionalAttrs (!upstreamInstalls) {
    installPhase = ''
      runHook preInstall
      ${dirs}${install}
      runHook postInstall
    '';
  }
)
