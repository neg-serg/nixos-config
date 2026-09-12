{
  config,
  lib,
  pkgs,
  ...
}:
let
  user = config.users.main.name or "neg";
  userData = lib.attrByPath [ "users" "users" user ] { } config;
  homeDir = lib.attrByPath [ "home" ] "/home/${user}" userData;

  # dsh model policy: keep the deployment on the V4.1 route everywhere.
  #
  # @deepseek-ai/dsh-llm-deepseek ships four catalog entries — the V4.1 id
  # (`deepseek-flash`, the only one with image input and the in-history
  # system-prompt update) plus three V4-era ones (`deepseek-v4-flash`,
  # `deepseek-v4-pro`, `deepseek-v4-flash-vision-exp`) that the model picker
  # still offers and that describe themselves with V4 capability metadata.
  # The provider config is settings-backed (namespace `llm-deepseek`, same as
  # `llm-pi-ai` in the user's settings), so one managed block in
  # ~/.dsh/settings.yaml narrows the catalog for every profile at once — web
  # GUI, TUI, subagents and the title model — and hot-reloads without a restart.
  #
  # The second block pins the default model and thinking level for new sessions
  # in every profile. Runtime switches (the session model picker, and the
  # /fast, /smart and /effort commands from dsh-mode) change the same keys, so
  # they survive only until the next rebuild or login, when the managed value
  # is restored.
  #
  # The user owns settings.yaml, so blocks are marker-delimited and only they
  # are rewritten; an existing hand-written section with the same top-level key
  # is replaced wholesale (the service's schema fills the rest from defaults,
  # since the composed rows carry no config of their own).
  blocks = [
    {
      marker = "dsh-models";
      key = "llm-deepseek";
      body = ''
        # dsh-models: begin (managed by modules/user/nix-maid/apps/dsh-models.nix)
        # V4.1-only provider catalog: the shipped list also offers deepseek-v4-flash,
        # deepseek-v4-pro and deepseek-v4-flash-vision-exp, which carry V4-era
        # capability metadata (text-only, no in-history system-prompt update).
        llm-deepseek:
          models:
            - id: deepseek-flash
              name: DeepSeek-V41-Flash
              inputModalities:
                - text
                - image
        # dsh-models: end
      '';
    }
    {
      marker = "dsh-agent-default-model";
      key = "agent-default-model";
      body = ''
        # dsh-agent-default-model: begin (managed by modules/user/nix-maid/apps/dsh-models.nix)
        # Deployment-wide default for new sessions: the V4.1 route only. Runtime
        # switches (/fast, /smart, /effort, the session model picker) revert on
        # the next rebuild or login.
        agent-default-model:
          provider: deepseek-official
          model: deepseek-flash
          reasoningEffort: high
        # dsh-agent-default-model: end
      '';
    }
  ];

  blocksJson = pkgs.writeText "dsh-models-blocks.json" (builtins.toJSON blocks);

  patch = pkgs.writeText "dsh-models-settings.py" ''
    import json
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    if not path.exists():
        print(f"dsh-models: {path} absent — nothing to do")
        sys.exit(0)

    blocks = json.loads(pathlib.Path(sys.argv[2]).read_text(encoding="utf-8"))
    src = path.read_text(encoding="utf-8")
    lines = src.split("\n")


    def drop(start: int, stop: int) -> None:
        del lines[start:stop]


    def remove(key: str, begin: str, end: str) -> None:
        """Drop the managed block, else a hand-written section for the same key."""
        bi = next((i for i, line in enumerate(lines) if line.startswith(begin)), None)
        if bi is not None:
            ei = next(
                (i for i in range(bi, len(lines)) if lines[i].startswith(end)),
                None,
            )
            if ei is None:
                raise SystemExit(f"dsh-models: {path}: unterminated managed block {begin}")
            drop(bi, ei + 1)
            return
        # A hand-written section: replace it up to the next top-level key so two
        # `key:` entries can never coexist in one YAML document.
        own = next((i for i, line in enumerate(lines) if line.startswith(key + ":")), None)
        if own is None:
            return
        stop = len(lines)
        for i in range(own + 1, len(lines)):
            line = lines[i]
            if line.strip() and not line[0].isspace() and not line.startswith("#"):
                stop = i
                break
        drop(own, stop)


    for block in blocks:
        remove(block["key"], f"# {block['marker']}: begin", f"# {block['marker']}: end")

    # Drop the blank separators left in front of the insertion point, then
    # append every block at EOF so a user edit above them is never disturbed.
    while len(lines) > 1 and lines[-1] == "" and lines[-2] == "":
        lines.pop()
    if lines and lines[-1] != "":
        lines.append("")
    for block in blocks:
        lines.extend(block["body"].rstrip("\n").split("\n"))
        lines.append("")
    while lines and lines[-1] == "":
        lines.pop()
    out = "\n".join(lines) + "\n"

    if out == src:
        print(f"dsh-models: {path}: managed blocks already current")
        sys.exit(0)
    path.write_text(out, encoding="utf-8")
    print(f"dsh-models: {path}: wrote {len(blocks)} managed block(s)")
  '';

  ensure = pkgs.writeShellScript "dsh-models-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    ${lib.getExe pkgs.python3} ${patch} "${homeDir}/.dsh/settings.yaml" ${blocksJson}
  '';
in
{
  # Runs on every rebuild (as the user, so the settings file stays user-owned)
  # and on every login — same pattern as dsh-tui-ru.
  system.activationScripts.dshModels = lib.stringAfter [ "users" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-models = {
    enable = true;
    description = "dsh-models — keep ~/.dsh/settings.yaml on the V4.1 model policy";
    after = [ "network.target" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
