{lib}: name: text: {
  # Keep activation quiet: rely on forceful file install, without per-file
  # activation steps. If a conflicting directory exists at the target path,
  # Home Manager will report it; such cases are rare for ~/.local/bin entries.
  home.file.".local/bin/${name}" = {
    # Mark executable and allow replacing an existing file; lower priority to allow overrides
    executable = lib.mkDefault true;
    force = lib.mkDefault true;
    inherit text;
  };
}
