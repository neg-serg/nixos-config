{
  lib,
  python3Packages,
  hidapi,
}:
python3Packages.buildPythonApplication rec {
  pname = "genlc";
  version = "0.1.0";

  format = "pyproject";
  src = ./.;

  nativeBuildInputs = with python3Packages; [
    poetry-core # Build backend for poetry-based pyproject.toml
  ];

  propagatedBuildInputs = with python3Packages; [
    hid # Python HID API wrapper (PyPI: hid) for USB HID communication
    click # CLI framework for the genlc command
  ];

  # Ensure hidapi system library is available at runtime
  buildInputs = [ hidapi ];

  preFixup = ''
    wrapProgram "$out/bin/genlc" \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ hidapi ]}
  '';

  meta = with lib; {
    description = "Unofficial CLI for controlling Genelec SAM loudspeakers via GLM adapter";
    homepage = "https://github.com/neg-serg/genlc";
    license = licenses.gpl3;
    platforms = platforms.linux;
    mainProgram = "genlc";
  };
}
