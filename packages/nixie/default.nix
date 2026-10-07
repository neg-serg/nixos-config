# The nixie workbench: the lamp drawn off-screen on the GPU, and its geometry
# checked against the data sheet's drawing. The wrapper hands the binary the
# Vulkan loader and glslangValidator, which it needs at run time.
{ lib, rustPlatform, pkg-config, vulkan-loader, glslang }:

rustPlatform.buildRustPackage {
  pname = "nixie";
  version = "0.1.0";
  src = ./.;
  cargoLock.lockFile = ./Cargo.lock;
  nativeBuildInputs = [ pkg-config ];
  postInstall = ''
    wrapProgram $out/bin/nixie \
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ vulkan-loader ]} \
      --set NIXIE_GLSLANG ${glslang}/bin/glslangValidator
  '';
  meta = {
    description = "Off-screen Vulkan render of the greeter's nixie tubes";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
