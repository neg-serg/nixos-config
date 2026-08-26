{
  lib,
  stdenv,
  fetchFromGitHub,
  meson,
  ninja,
  pkg-config,
  glib,
  systemd,
  pam,
  gtk4,
}:

stdenv.mkDerivation {
  pname = "atrium";
  version = "0.4.0";

  src = fetchFromGitHub {
    owner = "kavau";
    repo = "atrium";
    rev = "v0.4.0";
    hash = "sha256-lF/bMBAPmQjjoyBSbE665OCDD3HrHP7/VfOrKf+hTtg=";
  };

  nativeBuildInputs = [
    meson
    ninja
    pkg-config
    glib # glib-compile-resources for the GTK4 greeter gresource
  ];

  buildInputs = [
    systemd # libsystemd + libudev
    pam
    gtk4 # GTK4 graphical greeter
  ];

  mesonFlags = [ "-Ddist=arch" ];

  # Upstream hardcodes Arch FHS paths (/usr/lib/systemd/system, /etc/pam.d,
  # /etc, /usr/lib/sysusers.d, /usr/lib/tmpfiles.d). Redirect them into the
  # Nix store prefix/sysconfdir so meson install never writes outside $out.
  # The source-install sysusers/tmpfiles hooks are dropped: nixpkgs builds do
  # not use DESTDIR, so those hooks would run on the build machine.
  postPatch = ''
    substituteInPlace meson.build \
      --replace "install_dir:   '/usr/lib/systemd/system'" "install_dir:   get_option('prefix') / 'lib/systemd/system'" \
      --replace "install_dir: '/etc/pam.d'" "install_dir: get_option('sysconfdir') / 'pam.d'" \
      --replace "install_dir: '/etc'" "install_dir: get_option('sysconfdir')" \
      --replace "install_dir: '/usr/lib/sysusers.d'" "install_dir: get_option('prefix') / 'lib/sysusers.d'" \
      --replace "install_dir: '/usr/lib/tmpfiles.d'" "install_dir: get_option('prefix') / 'lib/tmpfiles.d'"
    sed -i -e '/meson.add_install_script/d' -e '/skip_if_destdir: true)/d' meson.build
  '';

  meta = with lib; {
    description = "Wayland multiseat display manager";
    homepage = "https://github.com/kavau/atrium";
    license = licenses.gpl2Plus;
    mainProgram = "atrium";
    platforms = platforms.linux;
    maintainers = [ ];
  };
}
