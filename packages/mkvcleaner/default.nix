{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "mkvcleaner";
  version = "1.1.0";

  src = fetchFromGitHub {
    owner = "etu";
    repo = "mkvcleaner";
    rev = version;
    hash = "sha256-0jVw1nneP8k0v1VSCnnQnX61o8wjtOw1QnTwnuYr5k8=";
  };

  vendorHash = "sha256-UO6qcgd39PRXSnfE8kTuyug8o7VRhnyfTjLGVWGYxfc=";

  ldflags = ["-s" "-w"];

  meta = with lib; {
    description = "Cleans unwanted tracks from video files";
    homepage = "https://github.com/etu/mkvcleaner";
    license = licenses.gpl3Only;
    maintainers = with maintainers; [];
    mainProgram = "mkvcleaner";
  };
}
