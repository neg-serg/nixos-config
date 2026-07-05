{
  lib,
  stdenvNoCC,
  inputs,
  makeWrapper,
}:
let
  version = "0.7.1+${inputs.openagentscontrol.shortRev or "dirty"}";
in
stdenvNoCC.mkDerivation {
  pname = "openagentscontrol";
  inherit version;

  src = inputs.openagentscontrol;

  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    share=$out/share/openagentscontrol

    install -d $share/agent/core
    install -d $share/agent/subagents/core
    install -d $share/agent/subagents/code
    install -d $share/agent/subagents/development
    install -d $share/agent/subagents/system-builder
    install -d $share/agent/subagents/test
    install -d $share/agent/subagents/utils
    install -d $share/agent/meta
    install -d $share/agent/content
    install -d $share/agent/data
    install -d $share/command
    install -d $share/command/openagents
    install -d $share/command/openagents/new-agents
    install -d $share/command/prompt-engineering
    install -d $share/context/core/standards
    install -d $share/context/core/workflows
    install -d $share/context/core/context-system/operations
    install -d $share/context/core/context-system/guides
    install -d $share/context/core/context-system/standards
    install -d $share/context/core/system
    install -d $share/context/project
    install -d $share/context/project-intelligence
    install -d $share/context/development/principles
    install -d $share/context/ui/web
    install -d $share/context/ui/web/design/lookup
    install -d $share/context/ui/web/design/guides
    install -d $share/context/ui/web/design/examples
    install -d $share/context/ui/web/design/concepts
    install -d $share/context/content-creation/principles
    install -d $share/context/content-creation/formats
    install -d $share/context/content-creation/workflows
    install -d $share/context/openagents-repo/lookup
    install -d $share/context/openagents-repo/guides
    install -d $share/context/openagents-repo/examples
    install -d $share/context/openagents-repo/core-concepts
    install -d $share/context/openagents-repo/quality
    install -d $share/context/openagents-repo/plugins/context/capabilities
    install -d $share/context/openagents-repo/plugins/context/architecture
    install -d $share/context/openagents-repo/plugins/context/reference
    install -d $share/context/system-builder-templates
    install -d $share/context/external-libraries
    install -d $share/context/domain-specific
    install -d $share/skills/task-management/scripts
    install -d $share/skills/smart-router-skill/config
    install -d $share/skills/smart-router-skill/scripts
    install -d $share/skills/context7
    install -d $share/skills/context-manager
    install -d $share/tool/gemini
    install -d $share/tool/env
    install -d $share/plugin
    install -d $share/profiles
    install -d $share/scripts
    install -d $share/prompts
    install -d $out/bin

    # Copy .opencode/ tree if it exists in src
    if [ -d .opencode ]; then
      cp -r .opencode/agent/* $share/agent/ 2>/dev/null || true
      cp -r .opencode/command/* $share/command/ 2>/dev/null || true
      cp -r .opencode/context/* $share/context/ 2>/dev/null || true
      cp -r .opencode/skills/* $share/skills/ 2>/dev/null || true
      cp -r .opencode/tool/* $share/tool/ 2>/dev/null || true
      cp -r .opencode/plugin/* $share/plugin/ 2>/dev/null || true
      cp -r .opencode/profiles/* $share/profiles/ 2>/dev/null || true
      cp -r .opencode/scripts/* $share/scripts/ 2>/dev/null || true
      cp -r .opencode/prompts/* $share/prompts/ 2>/dev/null || true
      cp .opencode/config.json $share/ 2>/dev/null || true
      cp .opencode/opencode.json $share/ 2>/dev/null || true
    fi

    # Copy top-level registry
    cp registry.json $share/ 2>/dev/null || true

    # Create oac wrapper script
    cat > $out/bin/oac <<'EOF'
    #!/usr/bin/env bash
    # OpenAgentsControl — NixOS integration
    SHARE="''${OPENAGENTSCONTROL_SHARE:-@share@}"
    if [ "$1" = "install" ]; then
      target="''${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
      echo "→ Linking agents into $target"
      mkdir -p "$target"
      for dir in agent command context skills tool plugin profiles scripts prompts; do
        if [ -d "$SHARE/$dir" ]; then
          rsync -av --ignore-existing "$SHARE/$dir/" "$target/$dir/" 2>/dev/null \
            || cp -rn "$SHARE/$dir/"* "$target/$dir/"
        fi
      done
      if [ -f "$SHARE/config.json" ]; then cp -n "$SHARE/config.json" "$target/"; fi
      echo "✓ Done. Use: opencode --agent OpenAgent"
    elif [ "$1" = "share" ]; then
      echo "OpenAgentsControl files: $SHARE"
      ls -la "$SHARE"
    else
      cat <<HELP
    OpenAgentsControl v${version} (NixOS package)

    Commands:
      oac install   — Link agent/context files into ~/.config/opencode/
      oac share     — Show package share directory
      oac help      — This help

    After install, start with:
      opencode --agent OpenAgent
    HELP
    fi
    EOF
    substituteInPlace $out/bin/oac --replace-fail '@share@' "$share"
    chmod +x $out/bin/oac
  '';

  meta = with lib; {
    description = "AI agent framework for plan-first development workflows with approval-based execution (agents + contexts for OpenCode)";
    homepage = "https://github.com/darrenhinde/OpenAgentsControl";
    license = licenses.mit;
    platforms = platforms.all;
    mainProgram = "oac";
  };
}
