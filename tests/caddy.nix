{
  name = "caddy-test";
  nodes = {
    server = {...}: {
      services.caddy = {
        enable = true;
        virtualHosts."localhost".extraConfig = ''
          respond "Hello, world!"
        '';
      };
      networking.firewall.allowedTCPPorts = [80 443];
    };
  };

  testScript = ''
    server.wait_for_unit("caddy.service")
    server.wait_for_open_port(80)
    server.succeed("curl --fail http://localhost | grep 'Hello, world!'")
  '';
}
