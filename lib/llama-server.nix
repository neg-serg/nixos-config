# llama-server unit skeleton — single purpose: build the `systemd.services.<name>`
# definition shared by the llama-server modules (modules/llm/llama-server.nix and
# llama-server-flash-next.nix). Exposed as config.lib.neg.llamaServer via
# modules/core/neg.nix; only description/ExecStart/user differ between callers.
{ lib }:
{
  # mkService { description, execStart, user } -> systemd unit attrset.
  # No wantedBy/requiredBy: manual start only (`systemctl start <name>`).
  # GPU access comes from the render/video supplementary groups.
  mkService =
    {
      description,
      execStart,
      user,
    }:
    {
      inherit description;
      after = lib.singleton "network.target";
      serviceConfig = {
        Type = "simple";
        User = user;
        SupplementaryGroups = [
          "render"
          "video"
        ];
        ExecStart = execStart;
        Restart = "on-failure";
        RestartSec = 5;
      };
    };
}
