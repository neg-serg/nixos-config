{pkgs, ...}: {
  environment.systemPackages = [
    pkgs.choose # human-friendly and fast alternative to cut and (sometimes) awk
    pkgs.enca # Extremely Naive Charset Analyser - detects and converts text file encoding
    pkgs.grex # generate regular expressions from user-provided test cases
    pkgs.grc # Generic Colouriser - colorizes output of commands like ping, traceroute, gcc, etc.
    pkgs.par # paragraph reformatter for text (useful for long lines)
    pkgs.sad # CLI tool to search and replace in files (Selective ADiting)
    pkgs.sd # intuitive find & replace CLI (sed alternative)
    pkgs.translate-shell # command-line translator using Google Translate, Bing Translator, etc.
  ];
}
