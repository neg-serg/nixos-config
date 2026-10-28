##
# Package: mi-ugens
# Purpose: Mutable Instruments eurorack modules ported to SuperCollider
#   (Clouds, Elements, Rings, Plaits, Braids, Tides, Warps, Grids, Verb, …).
#   Server plugins (.so) plus SC class files.
# Source: https://github.com/v7b1/mi-UGens
{
  lib,
  mkScPlugin,
  fetchFromGitHub,
  scPluginFarm,
}:
let
  # MiBraids links a static libsamplerate that upstream keeps as a git
  # submodule (fetchFromGitHub does not fetch submodules). Fetch the exact
  # submodule rev and unpack it into place before configuring.
  libsamplerate = fetchFromGitHub {
    owner = "libsndfile";
    repo = "libsamplerate";
    rev = "2ccde9568cca73c7b32c97fefca2e418c16ae5e3";
    hash = "sha256-GmgfmdrawAK8ktKtMgHMnzD2p80e373YNYlGg1edF/Q=";
  };
in
mkScPlugin {
  pname = "mi-ugens";
  version = "unstable-2026-04-10";

  src = fetchFromGitHub {
    owner = "v7b1";
    repo = "mi-UGens";
    rev = "10f6824f68ad63475f67dfe3fe5016e2d2634f84";
    hash = "sha256-16XeG3wXGPkiLd9oi6ZNF7jbndbKeVvf6hP/Verm2zg=";
  };

  postUnpack = ''
    rm -rf "$sourceRoot/projects/MiBraids/libsamplerate"
    cp -r ${libsamplerate} "$sourceRoot/projects/MiBraids/libsamplerate"
    chmod -R u+w "$sourceRoot/projects/MiBraids/libsamplerate"
  '';

  inherit scPluginFarm;

  # Local-only build (substitute=false) on Zen 5 — -march=native is safe and
  # speeds up the DSP-heavy MI modules (Clouds, Rings, Plaits). Realtime
  # audio: no -ffast-math (NaN/denormal semantics must stay IEEE-754).
  env.NIX_CFLAGS_COMPILE = "-march=native";

  # Parallel make race: MiBraids links libsamplerate.a by path without a
  # declared dependency, so the first parallel pass can fail with "No rule to
  # make target ... libsamplerate.a". Build that target first, then the rest.
  preBuild = ''
    cmake --build . --target samplerate
  '';

  installDir = "mi-UGens";
  install = ''
    mv "$out/mi-UGens"/*.so "$pluginsDir/"
    cp -r "$out/mi-UGens/Classes" "$extdir/"
    cp -r "$out/mi-UGens/HelpSource" "$extdir/"
    rm -rf "$out/mi-UGens"
  '';

  meta = lib.mkMeta {
    description = "Mutable Instruments eurorack modules as SuperCollider UGens";
    homepage = "https://github.com/v7b1/mi-UGens";
    license = lib.licenses.gpl3Plus;
  };
}
