{ lib, runCommand, python3, dsh }:
# Patched copy of the dsh web profile's @deepseek-ai package tree: the
# compiled web bundle hardcodes a few Chinese UI strings (search/glob result
# banners, terminal-card labels, truncation notices) that ignore the locale
# preference. patch.py rewrites them to English. The profile's @deepseek-ai
# symlink (dsh-market.nix `dshAiStore`) points here instead of at the
# unpatched harness copy, so the served web app is English.
#
# The copy is a plain `cp -a` of the built dsh tree plus a string patch —
# no network, no rebuild of dsh itself. The WHOLE node_modules tree is
# duplicated, not just the @deepseek-ai scope: module resolution walks up to
# the nearest node_modules ancestor, so intra-scope imports
# (@deepseek-ai/cordis -> @deepseek-ai/cosmokit) and hoisted non-scope deps
# (zod, …) must sit beside the scope, exactly as in the harness tree. A
# flat scope-only copy lost that ancestor and every plugin failed to import
# with ERR_MODULE_NOT_FOUND, crashing dsh at boot. The profile's
# @deepseek-ai symlink points at `$out/node_modules/@deepseek-ai`.
runCommand "dsh-web-en-${dsh.version or "0.1.0-rc.6"}" {
  nativeBuildInputs = [ python3 ];
  meta = {
    description = "dsh web @deepseek-ai tree with hardcoded Chinese UI copy replaced by English";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
} ''
  mkdir -p "$out/node_modules"
  cp -a '${dsh}/lib/node_modules/@deepseek-ai/dsh/node_modules/.' "$out/node_modules/"
  chmod -R u+w "$out"
  python3 '${./patch.py}' "$out/node_modules/@deepseek-ai"
''
