{ pkgs, ... }:
{
  fonts.fontDir.enable = true; # add fontdir support for nixos
  fonts.packages = [
    pkgs.material-symbols # Material Design icon font for panels/quickshell
    pkgs.noto-fonts # Google Noto multilingual fonts
    pkgs.noto-fonts-cjk-sans # CJK sans-serif fonts
    pkgs.noto-fonts-color-emoji # Color emoji fonts
    pkgs.ttf-code2000 # Code2000 shareware Unicode font (broad BMP script coverage)
    pkgs.ttf-code2001 # Code2001 freeware font: Plane 1 ancient/historic scripts (Linear B, Gothic, ...)
    pkgs.ttf-code2002 # Code2002 freeware font: Plane 2 rare CJK ideographs (Ext B-I)
    pkgs.ttf-code20x3 # Code20X3 freeware font: Plane 3 CJK Extensions G/H
  ];

  # Themes and app configs still name JetBrains Mono, FiraCode and Inter; map
  # them to the fonts that remain installed (Iosevka Nerd for mono symbols,
  # Outfit for UI) instead of a generic fallback. Both spellings are aliased:
  # the real Nerd Font families carry no space ("FiraCode Nerd Font Mono"),
  # while a few configs here spell them with one ("Fira Code Nerd Font Mono").
  fonts.fontconfig.localConf = ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "fonts.dtd">
    <fontconfig>
      <alias binding="same">
        <family>JetBrains Mono Nerd Font</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>JetBrainsMono Nerd Font</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>JetBrainsMono Nerd Font Mono</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>JetBrains Mono Nerd Font Mono</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>Fira Code Nerd Font</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>FiraCode Nerd Font</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>Fira Code Nerd Font Mono</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>FiraCode Nerd Font Mono</family>
        <prefer><family>Iosevka</family></prefer>
      </alias>
      <alias binding="same">
        <family>Inter</family>
        <prefer><family>Outfit</family></prefer>
      </alias>
      <alias binding="same">
        <family>Inter Display</family>
        <prefer><family>Outfit</family></prefer>
      </alias>
    </fontconfig>
  '';
}
