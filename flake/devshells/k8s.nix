{
  pkgs,
  ...
}:
pkgs.mkShell {
  packages = [
    pkgs.kubectl # Kubernetes CLI
    pkgs.kubectx # fast switch Kubernetes contexts
    pkgs.kubernetes-helm # Helm package manager
    pkgs.scaleway-cli # Scaleway cloud CLI
    pkgs.kubecolor # Colorize kubectl output
  ];
}
