{
  inputs,
  ...
}: {
  _module.args.yandexBrowserProvider =
    if inputs ? "yandex-browser"
    then (pkgs: inputs."yandex-browser".packages.${pkgs.stdenv.hostPlatform.system})
    else null;
}
