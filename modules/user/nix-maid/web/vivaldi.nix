{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  cfg = config.features.web.vivaldi;
  webEnabled = config.features.web.enable or false;
  guiEnabled = config.features.gui.enable or false;

  # Extension install strategy — no ExtensionInstallForcelist (force-installed
  # extensions make Chromium treat pages as "managed by your organization" and
  # block DevTools everywhere; SurfingKeys/Tampermonkey run on every page), no
  # --load-extension (unpacked developer-mode extensions trigger Vivaldi's
  # "Disable developer mode extensions" popup on EVERY startup), and no
  # ExtensionSettings normal_installed policy (Vivaldi 8.x ignores
  # /etc/chromium policies). Instead SurfingKeys/Tampermonkey are pre-installed
  # into the profile as NORMAL user extensions (location=1, exactly the layout
  # a store install produces: Default/Extensions/<id>/<version>_0/ + a
  # Preferences entry) by a systemd user service. Result: fully automatic,
  # no popup, no policy strings, user-removable via vivaldi://extensions.

  # Vivaldi bundles its own libffmpeg.so with all codecs (proprietary browser).
  # nixpkgs proprietaryCodecs=true replaces it with an outdated chromium-codecs-ffmpeg-extra
  # snap that lacks av_dynamic_hdr_smpte2094_app5_to_t35 → symbol lookup error.
  # We keep proprietaryCodecs=false (no snap download), but vivaldi-bin has libffmpeg.so
  # as DT_NEEDED and its RUNPATH only covers opt/vivaldi/lib/, not opt/vivaldi/ where
  # the bundled libffmpeg.so lives. So we patch the RUNPATH to include opt/vivaldi/.
  vivaldi-pkg = pkgs.vivaldi.override {
    # Wayland Ozone + Skia renderer (stable colors, no Vulkan video-overlay bug) +
    # VA-API hardware video decoding on AMD (radeonsi). Vulkan is disabled — it causes
    # a white-screen video overlay on Wayland (Chromium bug).
    # --force-color-profile=srgb is needed for fullscreen: Hyprland direct_scanout
    # bypasses compositor color management (cm=auto), so the GPU outputs in native
    # display gamut.  sRGB clamp keeps colors consistent windowed ↔ fullscreen.
    # --disable-features=WaylandWpColorManagerV1: Chromium's wp_color_manager_v1
    # protocol handshake with Hyprland cm=auto can fail on AMD, causing overbright
    # gamma and incorrect colors (vs Firefox which doesn't use this protocol).
    commandLineArgs = "--ozone-platform-hint=wayland --force-color-profile=srgb --enable-features=UseSkiaRenderer,VaapiVideoDecoder,VaapiVideoEncoder,VaapiIgnoreDriverChecks --disable-features=Vulkan,WaylandWpColorManagerV1";
    proprietaryCodecs = false;
  };

  # Patch RUNPATH on vivaldi-bin so the NEEDED libffmpeg.so (bundled, opt/vivaldi/)
  # is findable. nixpkgs's libPath only adds opt/vivaldi/lib but Vivaldi ships
  # libffmpeg.so in opt/vivaldi/ directly.
  vivaldi-fixed = vivaldi-pkg.overrideAttrs (old: {
    buildPhase = old.buildPhase + ''
      patchelf --add-rpath "$out/opt/vivaldi" opt/vivaldi/vivaldi-bin
    '';
  });

  # --- SurfingKeys + Tampermonkey: profile pre-install (normal extensions) ---
  # Fetch the .crx from the Chrome Web Store CDN (pinned sha256). When bumping
  # a version, update BOTH the version below and the hash (grab the new crx via
  # the same URL with prodversion=<recent> and sha256sum it).
  extension-crx = { id, sha256 }:
    pkgs.fetchurl {
      url = "https://clients2.google.com/service/update2/crx?response=redirect&prodversion=132.0.0.0&acceptformat=crx3&x=id%3D${id}%26installsource%3Dondemand%26uc";
      inherit sha256;
    };

  # .crx is a zip with a binary header — strip everything before the PK\x03\x04
  # zip magic, then unpack into the store.
  extension-unpacked = { name, crx }:
    pkgs.stdenv.mkDerivation {
      pname = name;
      version = "1";
      src = crx;
      dontUnpack = true; # .crx is not a source archive; we strip+unzip in buildPhase
      nativeBuildInputs = [ pkgs.python3 pkgs.unzip ];
      buildPhase = ''
        python3 -c "d=open('$src','rb').read(); open('e.zip','wb').write(d[d.index(b'PK\x03\x04'):])"
        unzip -q e.zip -d $out
      '';
      installPhase = "true";
    };

  tampermonkey = extension-unpacked {
    name = "tampermonkey-5.5.0";
    crx = extension-crx {
      id = "dhdgffkkebhmkfjojejmpbldmpobfkfo";
      sha256 = "bcaec082c439e11c4df683f43d07e9ac3d4439251d72b91c5b452f977dac15d5";
    };
  };

  surfingkeys = extension-unpacked {
    name = "surfingkeys-1.18.0";
    crx = extension-crx {
      id = "gfbliohnnapiefjpjlpjnehglfpaknnc";
      sha256 = "2131dfc164aa4714b09368a09ee1eae419e5dc7f1a6e290e681aa6bffdffc67d";
    };
  };

  extension-install-script = pkgs.writeText "vivaldi-extension-install.py" ''
    #!/usr/bin/env python3
    """Idempotently install Vivaldi extensions as normal user extensions
    (location=1): copy store dir into <profile>/Extensions/<id>/<version>_0/
    and register in Preferences. Prunes stale location=8 (--load-extension)
    entries. Safe to run any time; atomic JSON merge."""
    import argparse, json, os, shutil, sys

    ap = argparse.ArgumentParser()
    ap.add_argument("--profile", default=os.path.expanduser("~/.config/vivaldi/Default"))
    ap.add_argument("--extension", action="append", nargs=3,
                    metavar=("ID", "VERSION", "SRC"))
    args = ap.parse_args()

    prefs_path = os.path.join(args.profile, "Preferences")
    prefs = {}
    if os.path.exists(prefs_path):
        try:
            with open(prefs_path, encoding="utf-8") as f:
                prefs = json.load(f)
        except json.JSONDecodeError:
            print("warning: Preferences unreadable, backing up and starting fresh",
                  file=sys.stderr)
            os.rename(prefs_path, prefs_path + ".bak")

    settings = prefs.setdefault("extensions", {}).setdefault("settings", {})
    changed = False

    for key in [k for k, v in settings.items() if v.get("location") == 8]:
        del settings[key]
        changed = True

    for ext_id, version, src in (args.extension or []):
        version_dir = version + "_0"
        dest = os.path.join(args.profile, "Extensions", ext_id, version_dir)
        if not os.path.isdir(dest):
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            shutil.copytree(src, dest)
        want = {"path": ext_id + "/" + version_dir, "location": 1, "state": 1}
        if settings.get(ext_id) != want:
            settings[ext_id] = want
            changed = True

    if changed:
        tmp = prefs_path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(prefs, f, indent=2)
        os.replace(tmp, prefs_path)
        print("Preferences updated")
    else:
        print("up to date")
  '';
in
{
  config = mkIf (webEnabled && guiEnabled && cfg.enable) {

    environment.systemPackages = [
      vivaldi-fixed # Vivaldi browser (Chromium-based, with Wayland flags, patched libffmpeg.so rpath)
    ];

    # Chromium managed policies — most Chromium-based browsers read from here.
    # Vivaldi may or may not pick them up depending on the version (8.x sometimes ignores it).
    programs.chromium = {
      enable = true;
      extraOpts = {
        "PasswordManagerEnabled" = false;
        "BuiltInNotificationsSettings" = 2; # Blocked
        "MetricsReportingEnabled" = false;
        "SafeBrowsingProtectionLevel" = 1; # Standard
        "SearchSuggestEnabled" = false;
        "SyncDisabled" = false;
        "ShowHomeButton" = true;
        "BookmarkBarEnabled" = false;
        # Force-installed extensions (SurfingKeys/Tampermonkey) make DevTools
        # report "Your organization blocked DevTools on this page" — allow it.
        "DeveloperToolsAvailability" = 0; # Allowed everywhere

        # Default font: Iosevka everywhere (matches system-wide fontconfig default)
        "StandardFontFamily" = "Iosevka";
        "SerifFontFamily" = "Iosevka";
        "SansSerifFontFamily" = "Iosevka";
        "FixedFontFamily" = "Iosevka";
        "DefaultFontSize" = 15;
        "DefaultFixedFontSize" = 13;
      };
    };

    # Vivaldi-specific managed policies.
    # Vivaldi 8.x reads from /etc/vivaldi/policies/managed/ but sometimes ignores
    # /etc/chromium/policies/managed/.  Duplicate the relevant policies here.

    environment.etc."vivaldi/policies/managed/vivaldi-fonts.json" = {
      mode = "0444";
      text = builtins.toJSON {
        StandardFontFamily = "Iosevka";
        SerifFontFamily = "Iosevka";
        SansSerifFontFamily = "Iosevka";
        FixedFontFamily = "Iosevka";
        DefaultFontSize = 15;
        DefaultFixedFontSize = 13;
      };
    };

    environment.etc."vivaldi/policies/managed/devtools.json" = {
      mode = "0444";
      text = builtins.toJSON {
        DeveloperToolsAvailability = 0; # Allowed everywhere (blocked by force-installed extensions otherwise)
      };
    };


    # Browser UI font override via Vivaldi Custom UI Modifications.
    # Managed policies above only affect webpage fonts, not the browser chrome.
    # This CSS overrides the hardcoded Linux UI font-family in Vivaldi's common.css
    # (Cantarell / Noto Sans → Iosevka).
    # To activate: enable "Allow for using CSS modifications" in vivaldi://experiments,
    # then set Settings → Appearance → Custom UI Modifications → /etc/vivaldi/custom-ui/
    environment.etc."vivaldi/custom-ui/vivaldi-ui-font.css" = {
      mode = "0444";
      text = ''
        /* Override Vivaldi browser UI font on Linux — Iosevka, bigger and bolder */
        *, *:before, *:after {
          font-family: "Iosevka" !important;
          font-size: 15px !important;
          font-weight: 600 !important;
        }
      '';
    };

    # Pre-install SurfingKeys + Tampermonkey into the profile as normal user
    # extensions (see the strategy note at the top). Idempotent; also prunes
    # stale --load-extension entries. Runs at login, before Vivaldi autostart
    # in practice; self-heals on the next login if Vivaldi wins the race.
    systemd.user.services.vivaldi-extension-install = {
      description = "Install SurfingKeys and Tampermonkey into the Vivaldi profile";
      wantedBy = [ "default.target" ];
      serviceConfig = {
        Type = "oneshot";
        Restart = "on-failure";
        ExecStart = "${pkgs.python3}/bin/python3 ${extension-install-script} --extension dhdgffkkebhmkfjojejmpbldmpobfkfo 5.5.0 ${tampermonkey} --extension gfbliohnnapiefjpjlpjnehglfpaknnc 1.18.0 ${surfingkeys}";
      };
    };
  };
}
