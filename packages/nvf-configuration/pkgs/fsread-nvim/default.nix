{
  vimUtils,
  fetchFromGitHub,
}:
vimUtils.buildVimPlugin {
  pname = "fsread.nvim";
  version = "2024-11-03";

  src = fetchFromGitHub {
    owner = "neg-serg";
    repo = "fsread.nvim";
    rev = "ad341ed1e6452db51d5a3a581f3a0b581cbd2f48";
    sha256 = "1k7zcwigcvjnv76bk95w73pbd0cm6wd7i19dmsld1v8s72h240wb";
  };

  meta.homepage = "https://github.com/nullchilly/fsread.nvim";
}
