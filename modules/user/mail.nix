{pkgs, ...}: {
  # Core mail CLI clients (himalaya, neomutt, kyotocabinet) now install at the
  # system level so they are available even outside Home Manager sessions.
  environment.systemPackages = [
    pkgs.himalaya
    pkgs.kyotocabinet
    pkgs.neomutt
  ];
}
