{ pkgs, lib, config, ... }:
{
  environment.systemPackages = [
    # Network diagnostics
    pkgs.doggo # DNS client for humans
    pkgs.prettyping # fancy ping output
    pkgs.speedtest-cli # internet speed test
    pkgs.urlscan # extract URLs from text blobs
    pkgs.urlwatch # watch pages for changes
    pkgs.whois # domain info lookup

    # Remote access
    pkgs.abduco # CLI session detach
    pkgs.xxh # SSH wrapper for jumping into remote shells

    # Cloud tools

    pkgs."yandex-disk" # Yandex Disk sync client and daemon
  ] ++ (lib.optional (config.features.cli.yandexCloud.enable or false) pkgs."yandex-cloud");

}
