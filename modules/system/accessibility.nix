{
  # AT-SPI accessibility stack: enabling the GNOME module (a) provides the
  # org.a11y.Bus activation unit and (b) stops NixOS from exporting
  # NO_AT_BRIDGE=1 / GTK_A11Y=none — with those set, GTK applications never
  # publish accessibility trees at all. Those trees are what neru's axtree
  # hints, CUL semantic selectors and screen readers read.
  # The bus launcher's unit is declared in
  # modules/user/nix-maid/apps/dsh-desktop.nix, which resets the packaged
  # ExecStart (and passes no arguments: at-spi2-core 2.62 aborts on any argument
  # but `--launch-immediately`).
  services.gnome.at-spi2-core.enable = true;
}
