{
  # AI/LLM tools
  ai-tools = [
    "ai-studio" # local LLM app (new upstream rebrand)
    "lmstudio" # legacy name for older nixpkgs pins
  ];

  # Audio editors and instruments
  audio = [
    "ocenaudio" # audio editor
    "vital" # digital synth
  ];

  # Web browsers
  browsers = [
    "google-chrome" # Google Chrome
    "vivaldi" # Vivaldi Browser
    "microsoft-edge" # Microsoft Edge Browser
    "microsoft-edge-stable" # Microsoft Edge Browser (standard name)
  ];

  # Forensics analysis tools
  forensics-analysis = [
    "volatility3" # memory forensics
  ];

  # Forensics stego tools
  forensics-stego = [
    "stegsolve" # image stego analyzer
  ];

  # Combined forensics (convenience union)
  forensics = [
    "stegsolve" # image stego analyzer
    "volatility3" # memory forensics
  ];

  # Infrastructure-as-code tools
  iac = [
    "terraform"
  ];

  # Miscellaneous unfree packages
  misc = [
    "abuse" # side-scrolling shooter (LISP)
  ];
}
