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

  # dsh-models: keep the deployment on the V4.1 route everywhere.
  #
  # @deepseek-ai/dsh-llm-deepseek ships four catalog entries — the V4.1 id
  # (`deepseek-flash`, the only one with image input and the in-history
  # system-prompt update) plus three V4-era ones (`deepseek-v4-flash`,
  # `deepseek-v4-pro`, `deepseek-v4-flash-vision-exp`) that the model picker
  # still offers and that describe themselves with V4 capability metadata.
  # The provider config is settings-backed (namespace `llm-deepseek`, same as
  # `llm-pi-ai` in the user's settings), so one managed block in
  # ~/.dsh/settings.yaml narrows the catalog for every profile at once — web
  # GUI, TUI, subagents and the title model — and hot-reloads without a
  # restart.
  #
  # The user owns settings.yaml, so the block is marker-delimited and only that
  # block is rewritten; an existing hand-written `llm-deepseek:` section is
  # replaced wholesale (the provider's schema fills the rest from its defaults,
  # since the composed row carries no config of its own).
  patch = pkgs.writeText "dsh-models-settings.py" ''
    import pathlib
    import sys

    path = pathlib.Path(sys.argv[1])
    if not path.exists():
        print(f"dsh-models: {path} absent — nothing to do")
        sys.exit(0)

    BEGIN = "# dsh-models: begin"
    END = "# dsh-models: end"
    BLOCK = """\
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
    """

    src = path.read_text(encoding="utf-8")
    lines = src.split("\n")

    def cut(start: int, stop: int) -> None:
        del lines[start:stop]

    changed = False
    begin = next((i for i, line in enumerate(lines) if line.startswith(BEGIN)), None)
    if begin is not None:
        end = next(
            (i for i in range(begin, len(lines)) if lines[i].startswith(END)),
            None,
        )
        if end is None:
            raise SystemExit(f"dsh-models: {path}: unterminated managed block")
        cut(begin, end + 1)
        changed = True
    else:
        # A hand-written section: replace it up to the next top-level key so two
        # `llm-deepseek:` keys can never coexist in one YAML document.
        own = next((i for i, line in enumerate(lines) if line.startswith("llm-deepseek:")), None)
        if own is not None:
            stop = len(lines)
            for i in range(own + 1, len(lines)):
                line = lines[i]
                if line.strip() and not line[0].isspace() and not line.startswith("#"):
                    stop = i
                    break
            cut(own, stop)
            changed = True

    # Drop the blank separators left in front of the insertion point, then
    # append the block at EOF so a user edit above it is never disturbed.
    while len(lines) > 1 and lines[-1] == "" and lines[-2] == "":
        lines.pop()
    if lines and lines[-1] != "":
        lines.append("")
    lines.extend(BLOCK.rstrip("\n").split("\n"))
    out = "\n".join(lines) + "\n"

    if out == src:
        print(f"dsh-models: {path}: managed block already current")
        sys.exit(0)
    path.write_text(out, encoding="utf-8")
    print(f"dsh-models: {path}: wrote the V4.1-only provider catalog")
  '';

  ensure = pkgs.writeShellScript "dsh-models-ensure" ''
    set -eu
    export PATH=/run/current-system/sw/bin:$PATH
    ${lib.getExe pkgs.python3} ${patch} "${homeDir}/.dsh/settings.yaml"
  '';
in
{
  # Runs on every rebuild (as the user, so the settings file stays user-owned)
  # and on every login — same pattern as dsh-market / dsh-tui-ru.
  system.activationScripts.dshModels = lib.stringAfter [ "users" "dshMarketEnsure" ] ''
    ${lib.getExe' pkgs.util-linux "runuser"} -u ${user} -- env HOME=${homeDir} ${ensure} || true
  '';

  systemd.user.services.dsh-models = {
    enable = true;
    description = "dsh-models — keep ~/.dsh/settings.yaml on the V4.1 provider catalog";
    after = [ "network.target" ];
    before = [ "dsh.service" ];
    wantedBy = [ "default.target" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = ensure;
    };
  };
}
