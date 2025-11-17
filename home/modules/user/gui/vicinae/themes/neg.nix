let
  accent = "#005f87";
  accentSecondary = "#1f6f8f";
  background = "#030606";
  backgroundRaised = "#080f14";
  border = "#0b1c24";
  selection = "#002d59";
  selectionRaised = "#0c2738";
  text = "#b8c5d9";
  textMuted = "#90a4bd";
  textPlaceholder = "#7d93ae";
  link = "#58b6e2";
  linkVisited = "#a89cff";
in {
  meta = {
    version = 1;
    name = "neg";
    description = "Matches the walker/rofi dark teal theme";
    variant = "dark";
    inherits = "vicinae-dark";
  };

  colors = {
    core = {
      inherit accent background border;
      accent_foreground = "#eff5ff";
      foreground = text;
      secondary_background = backgroundRaised;
    };

    main_window = {
      inherit border;
    };
    settings_window = {
      inherit border;
    };

    accents = {
      blue = accent;
      cyan = "#289ec4";
      green = "#4fa388";
      magenta = "#b379d5";
      orange = "#dd8237";
      purple = "#7f7ce2";
      red = "#c15866";
      yellow = "#d3a652";
    };

    text = {
      default = text;
      muted = textMuted;
      danger = "#d67272";
      success = "#63c092";
      placeholder = textPlaceholder;
      selection = {
        background = selection;
        foreground = "#f5fbff";
      };
      links = {
        default = link;
        visited = linkVisited;
      };
    };

    input = {
      inherit border;
      border_focus = accent;
      border_error = "#d05f6b";
    };

    button.primary = {
      background = "#091318";
      foreground = "#d8e4f6";
      hover = {
        background = "#0f1f28";
      };
      focus = {
        outline = accent;
      };
    };

    list.item = {
      hover = {
        background = "#0c1820";
        foreground = text;
      };
      selection = {
        background = selection;
        foreground = "#eff6ff";
        secondary_background = selectionRaised;
        secondary_foreground = "#dae6f5";
      };
    };

    grid.item = {
      background = "#0b141c";
      hover = {
        outline = accentSecondary;
      };
      selection = {
        outline = accent;
      };
    };

    scrollbars = {
      background = "#0d2531";
    };

    loading = {
      bar = accent;
      spinner = text;
    };
  };
}
