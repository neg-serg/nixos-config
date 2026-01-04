{
  vimUtils,
  fetchFromGitHub,
}:
vimUtils.buildVimPlugin {
  pname = "fsread.nvim";
  version = "2024-11-03";

  src = fetchFromGitHub {
    owner = "nullchilly";
    repo = "fsread.nvim";
    rev = "a637bf048f733def7c5c46f5bf482f93a8311b29";
    sha256 = "1ais9bp8gaqckaznwj4s634ys9jivdvzimhimssrkiw0r2gq3k0a";
  };

  meta.homepage = "https://github.com/nullchilly/fsread.nvim";
}
