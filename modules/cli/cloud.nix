{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.kubectl # Kubernetes CLI
    pkgs.kubectx # fast switch Kubernetes contexts
    pkgs.kubernetes-helm # Helm package manager
    pkgs.nextcloud-client # Nextcloud CLI sync client (nextcloudcmd)
    pkgs.scaleway-cli # Scaleway cloud CLI
    pkgs."yandex-cloud" # Yandex Cloud CLI
    pkgs."yandex-disk" # Yandex Disk sync client and daemon
  ];
}
