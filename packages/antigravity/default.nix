{
  writeShellApplication,
  python3,
}:
writeShellApplication {
  name = "antigravity";
  runtimeInputs = [python3];
  text = ''
    exec python3 -m antigravity "$@"
  '';
}
