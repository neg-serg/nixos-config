{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.doggo # DNS client for humans
    pkgs.prettyping # fancy ping output
    pkgs.speedtest-cli # internet speed test
    pkgs.urlscan # extract URLs from text blobs
    pkgs.urlwatch # watch pages for changes
    pkgs.whois # domain info lookup
  ];
}
