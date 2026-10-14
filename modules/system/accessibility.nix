{
  # AT-SPI accessibility stack: enabling the GNOME module (a) provides the
  # org.a11y.Bus activation unit and (b) stops NixOS from exporting
  # NO_AT_BRIDGE=1 / GTK_A11Y=none — with those set, GTK applications never
  # publish accessibility trees at all. Those trees are what neru's axtree
  # hints, CUL semantic selectors and screen readers read.
  # The --a11y=1 bus launcher (sets org.a11y.Status.IsEnabled=true) stays in
  # modules/user/nix-maid/apps/dsh-desktop.nix — the packaged unit this module
  # installs does not pass that flag.
  services.gnome.at-spi2-core.enable = true;
}
