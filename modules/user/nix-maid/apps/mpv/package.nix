{
  pkgs,
  lib,
  config,
  neg,
  repoRoot,
  ...
}:
let
  r = neg.rooted repoRoot;

  # Repo-local mpv scripts (files/mpv/*.lua): each becomes one
  # `$out/share/mpv/scripts/<name>.lua` for the wrapper below.
  mkRepoScript =
    name:
    pkgs.stdenv.mkDerivation {
      pname = "mpv-script-${name}";
      version = "0.1.0";
      src = r.path "files/mpv/${name}.lua";
      scriptName = "${name}.lua";
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out/share/mpv/scripts
        cp $src $out/share/mpv/scripts/$scriptName
      '';
    };

  # --- Scripts & Package ---
  scriptPkgs = [
    pkgs.mpvScripts.cutter # cut/extract video segments from mpv
    pkgs.mpvScripts.mpris # MPRIS integration for media keys
    pkgs.mpvScripts.quality-menu # quality/stream switcher menu
    pkgs.mpvScripts.sponsorblock # skip sponsors on YouTube videos
    pkgs.mpvScripts.thumbfast # instant thumbnails in seek bar
    pkgs.mpvScripts.uosc # modern minimalist UI with controls
    (mkRepoScript "hdr-auto-switch") # auto-switch Hyprland cm to HDR on HDR content
    (mkRepoScript "trash") # move the current file to /tmp/trash (D)
  ];

  mpvUnwrapped =
    (pkgs.mpv-unwrapped.override {
      vapoursynthSupport = true;
    }).overrideAttrs
      (old: {
        env.NIX_CFLAGS_COMPILE =
          toString (old.env.NIX_CFLAGS_COMPILE or "")
          + " -O3 -ftree-parallelize-loops=8 -floop-parallelize-all";
      });

  # `youtubeSupport = false` drops the upstream wrapper's PATH suffix with
  # yt-dlp. That suffix is what kept a 692 MiB python closure (151 store paths)
  # in every system generation; yt-dlp itself now comes from the on-demand
  # launcher in modules/user/nix-maid/web/yt-dlp.nix, which sits in the system
  # PATH, so mpv's ytdl_hook still finds it — it builds on the first URL that
  # needs it. Upstream mpv only uses this flag for that fallback path; the
  # ytdl_hook script itself stays compiled in.
  mpvPackage = pkgs.mpv.override {
    mpv-unwrapped = mpvUnwrapped;
    scripts = scriptPkgs;
    youtubeSupport = false;
  };
in
{
  config = lib.mkIf (config.lib.neg.enabled "gui") (
    lib.mkMerge [
      {
        # Install Package
        # System-wide (not user profile): Hyprland binds and `pl` launch mpv from
        # non-login PATHs where ~/.nix-profile/bin is absent.
        environment.systemPackages = [ mpvPackage ];
      }
    ]
  );
}
