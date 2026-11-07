# Shared builder for the ArtCraft desktop apps: VectorCraft, FigCraft,
# SoundCraft, DeckCraft, GridCraft and SolidCraft.
#
# Six upstream repositories, one shape: an egui/wgpu Rust workspace that builds
# a GUI binary plus a `-cli` companion, and a `packaging/linux/` tree that
# stages the same desktop entry, MIME xml, AppStream metainfo and hicolor icons
# as the official .deb/.rpm. Everything that differs between the apps — version,
# hashes, file paths, native libraries — is data passed in by
# packages/<app>/default.nix.
#
# Reachable as `pkgs.neg.functions.mkCraftApp`. It is a package builder, not a
# `lib` extension (unlike mkMeta): it returns a derivation.
#
# Why local packages when the pinned nixpkgs already carries four of the six:
# those recipes are several releases behind upstream (deckcraft 0.6.1 against
# 0.16.0), and the module installs every app as an on-demand launcher that
# builds the newest tag on first use.
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  makeWrapper,
  pkg-config,
  craft-fonts,
  vulkan-loader,
  libGL,
  libxkbcommon,
  wayland,
  libx11,
  libxcb,
  libxcursor,
  libxi,
  libxrandr,
  dbus,
}:
# The dlopen'ed, never linked runtime set every one of the six needs: winit
# (X11/Wayland/xkbcommon), wgpu (Vulkan, and GL through the libglvnd loader) and
# rfd's xdg-desktop-portal backend (libdbus, for file dialogs). nixpkgs' own
# recipes for these apps carry the same list. It lives here, not in the second
# argument set, so the `runtimeLibs` default can name it.
let
  commonRuntimeLibs = [
    vulkan-loader # wgpu's Vulkan backend
    libGL # wgpu's GL fallback (libEGL/libGL from libglvnd)
    libxkbcommon # winit keyboard handling (X11 and Wayland)
    wayland # libwayland-client (Wayland backend)
    libx11
    libxcb
    libxcursor
    libxi
    libxrandr
    dbus # xdg-desktop-portal file dialogs
  ];
in
{
  name,
  version,
  hash,
  cargoHash ? lib.fakeHash,
  owner ? "storytold",
  repo ? name,
  description,
  homepage,
  license ? [
    lib.licenses.mit
    lib.licenses.asl20
  ],
  mainProgram ? name,
  # Cargo workspace members to build (`-p`) and the binaries to wrap with the
  # runtime library path. Normally the same two; solidcraft additionally ships
  # `solvecraft-cli`, the pre-rename name of its CLI, from the CLI crate.
  crates ? [
    name
    "${name}-cli"
  ],
  binaries ? crates,
  appId ? "ai.storyteller.${name}",
  desktop ? "packaging/linux/${appId}.desktop",
  mime ? "packaging/linux/${appId}.mime.xml",
  metainfo ? "packaging/linux/${appId}.metainfo.xml.in",
  icons ? "assets/app-icon/hicolor",
  docs ? [
    "README.md"
    "NOTICE"
    "ATTRIBUTION.md"
    "LICENSE-MIT"
    "LICENSE-APACHE"
  ],
  runtimeLibs ? commonRuntimeLibs,
  extraRuntimeLibs ? [ ],
  extraBuildInputs ? [ ],
  extraNativeBuildInputs ? [ ],
  wrapperPath ? [ ],
}:
let
  allRuntimeLibs = runtimeLibs ++ extraRuntimeLibs;

  wrapperArgs = [
    "--prefix"
    "LD_LIBRARY_PATH"
    ":"
    (lib.makeLibraryPath allRuntimeLibs)
  ]
  ++ lib.optionals (wrapperPath != [ ]) [
    "--suffix"
    "PATH"
    ":"
    (lib.makeBinPath wrapperPath)
  ];
in
rustPlatform.buildRustPackage {
  pname = name;
  inherit version;

  src = fetchFromGitHub {
    inherit
      owner
      repo
      hash
      ;
    tag = "v${version}";
  };

  inherit cargoHash;

  # Same derivation shape nixpkgs uses for these apps: structured attributes so
  # `env` is a real attrset, and strict on native/build inputs (the wrapper and
  # pkg-config are build-time only, the runtime libraries are not).
  __structuredAttrs = true;
  strictDeps = true;

  # The Japanese (and Georgian) UI faces are an optional *build* input upstream:
  # the text crate's build script embeds every font listed in the
  # `fonts/manifest.txt` of the checkout named by CRAFT_FONTS_DIR. The official
  # releases always carry them, so the packaged app does too, and
  # CRAFT_FONTS_REQUIRED turns a silently font-less build into a build error.
  env = {
    CRAFT_FONTS_DIR = "${craft-fonts}";
    CRAFT_FONTS_REQUIRED = "1";
  };

  # Only the binaries the official Linux packages stage; `-p` also keeps the
  # wasm front end (and, for figcraft, the server) out of the build and $out/bin.
  # No `--locked`: the postPatch below drops manifest lines, so Cargo rewrites
  # the lockfile (pruning the entries that only existed for them). Versions
  # cannot drift — the build is offline against the vendor set pinned by
  # cargoHash.
  cargoBuildFlags = lib.concatMap (crate: [
    "-p"
    crate
  ]) crates;

  # `cargo vendor` copies only the crates the lockfile wires up, while Cargo
  # validates *every* `[patch]` entry against its git source before an offline
  # build. These workspaces carry patch lines for crates nothing depends on any
  # more (egui_demo_lib, egui_inspection, egui_system_font_provider — and, in
  # figcraft, also egui_kittest), whose trees are therefore absent from the
  # vendor set, and the build dies with:
  #
  #   error: patch location `https://github.com/storytold/egui.git?rev=…`
  #   does not contain packages matching `egui_demo_lib`
  #
  # Drop exactly those lines: every patch the resolver still needs is one that
  # some lock entry lists as a dependency, so it stays, and the resolution is
  # otherwise unchanged (the orphan entries were never consulted).
  postPatch = ''
    awk '
      # Pass 1: Cargo.lock — collect every crate named in a [[package]] dependency
      # list ("name" or "name 1.2.3" between `dependencies = [` and `]`).
      NR == FNR {
        if ($0 ~ /^dependencies = \[/) { in_deps = 1; next }
        if (in_deps && $0 ~ /^\]/) { in_deps = 0; next }
        if (in_deps && $0 ~ /^ "/) {
          d = $0
          sub(/^ "/, "", d)
          sub(/"?,?$/, "", d)
          sub(/ .*$/, "", d)
          dep[d] = 1
        }
        next
      }
      # Pass 2: Cargo.toml — keep every [patch.*] line whose crate is depended on.
      /^\[patch/ { in_patch = 1 }
      /^\[/ && $0 !~ /^\[patch/ { in_patch = 0 }
      in_patch && $0 ~ /^[A-Za-z0-9_-]+[ \t]*=/ {
        name = $0
        sub(/[ \t]*=.*/, "", name)
        if (!(name in dep)) {
          printf "pruned orphan [patch] entry: %s\n", name > "/dev/stderr"
          next
        }
      }
      { print }
    ' Cargo.lock Cargo.toml >Cargo.toml.pruned
    mv Cargo.toml.pruned Cargo.toml
  '';

  # Upstream's gate is `cargo xtask ci` over the whole tree: it wants a GPU, a
  # wasm target and real documents, so the shipped binaries are smoke-tested
  # instead (see the module that installs the launchers).
  doCheck = false;

  nativeBuildInputs = [
    makeWrapper
    pkg-config
  ]
  ++ extraNativeBuildInputs;

  # The dlopen'ed libraries above also go into buildInputs: pkg-config probes
  # them (alsa-sys, libdbus-sys) and anything that does link gets a RUNPATH.
  buildInputs = allRuntimeLibs ++ extraBuildInputs;

  postFixup = lib.concatMapStringsSep "\n" (
    binary: "wrapProgram \"$out/bin/${binary}\" ${lib.escapeShellArgs wrapperArgs}"
  ) binaries;

  # Desktop entry, MIME types, AppStream metainfo and icons: the same files
  # upstream's packaging/linux/package.sh installs for the .deb, so a file
  # manager sees the app as the handler for its formats. The package's own
  # share/ tree is deliberately never on the system XDG_DATA_DIRS — it lives in
  # the on-demand GC root — which is why the desktop entry the session sees is
  # shipped separately by the module.
  postInstall = ''
    install -Dm644 ${desktop} $out/share/applications/${appId}.desktop
    install -Dm644 ${mime} $out/share/mime/packages/${appId}.xml

    mkdir -p $out/share/metainfo
    sed \
      -e "s/@VERSION@/${version}/g" \
      -e "s/@DATE@/1970-01-01/g" \
      ${metainfo} \
      >$out/share/metainfo/${appId}.metainfo.xml

    mkdir -p $out/share/icons
    cp -R ${icons} $out/share/icons/hicolor

    mkdir -p $out/share/doc/${name}
    for doc in ${lib.concatStringsSep " " docs}; do
      if [ -f "$doc" ]; then
        install -m644 "$doc" $out/share/doc/${name}/
      fi
    done
  '';

  meta = lib.mkMeta {
    inherit
      description
      homepage
      license
      mainProgram
      ;
  };
}
