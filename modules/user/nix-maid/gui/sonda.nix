#
# sonda — a file manager that finds files by what is inside them (features.gui.sonda)
#
#
# Upstream: https://github.com/k4ditano/sonda (MIT). A file manager whose search knows the
# contents: photos by what they show, a PDF at the page, a recording at the minute, code at the
# line, all embedded locally by EmbeddingGemma 2 on llama.cpp (Vulkan). Its window is a pleamar
# scene (`share`-less: the `.plm`, the Lua and the shaders are compiled into the binary), so it
# needs pleamar or pleamar-wm on PATH — the package is `packages/sonda`, next to this module.
#
# ## What this module does, and what it does not
#
# It installs the binary and nothing else. Deliberately no session unit: `sonda` starts the reader
# (`sonda daemon`) by itself when the window needs it, and a permanent reader would walk the whole
# home and keep the GPU busy from login on. Upstream's own recipe for a session that always has the
# index ready is `sonda daemon` in the shell's autostart; the same effect here is a
# `systemd.user.services.sonda-daemon` with `WantedBy = [ "default.target" ]`, added when it is
# wanted rather than by default.
#
# The models are not in the store: `sonda setup` downloads EmbeddingGemma 2's text part and the
# picture/sound encoders (865 MB) from Hugging Face into `$XDG_DATA_HOME/sonda/models` the first
# time, and writes the window and the D-Bus service files next to them. Run it once after the first
# switch — it is idempotent and skips what is already there.
#
# The package also ships `$out/share/xdg-desktop-portal/portals/sonda.portal`
# (`UseIn=pleamar`, the Open/Save dialog). It is not wired into `xdg.portal`: this session runs
# `XDG_CURRENT_DESKTOP=Hyprland`, where the file chooser is the GTK portal (modules/user/xdg.nix),
# and switching it to sonda's would take that choice away from every other program.
#
{
  lib,
  pkgs,
  config,
  ...
}:
{
  config = lib.mkIf (config.lib.neg.enabled "gui" && config.features.gui.sonda.enable) {
    environment.systemPackages = [
      pkgs.sonda # file manager for pleamar-wm, searching files by what they contain
    ];
  };
}
