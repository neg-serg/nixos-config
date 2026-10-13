{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:
buildGoModule rec {
  pname = "iris";
  # Tagged release (2026-10-09). Before this the pin was unreleased main
  # c86c0244 (pre-v0.7.0), taken just for ghost-text = 2 — v0.7.0 shipped
  # that as a documented 3-mode option (0 = off, 1 = menu + ghost, 2 = ghost
  # only), along with the arrow-key, atuin/menu and history fixes.
  version = "0.7.3";

  src = fetchFromGitHub {
    owner = "versenilvis";
    repo = "iris";
    rev = "v0.7.3";
    hash = "sha256-7JdwXpt+EDU6fRjBf0kzHwCeB2NFwYk1rSZY790QIag=";
  };

  # Go module dependencies (charmbracelet lipgloss/glamour, cobra, modernc sqlite, ...).
  vendorHash = "sha256-9GZn8xxdWGeAfTjJXj7VF4gyFpsyrNUDHlM+oCxiUAs=";

  # [trantor] Shell-compatibility patches on top of v0.7.3:
  #
  # iris-select-fallthrough: the accept key (Tab) inserts the menu's current
  # suggestion when the menu is visible, otherwise falls through to the shell
  # so the key keeps its normal meaning (Tab: fzf-on-tab / ~/m/new expansion).
  # Upstream always consumes the key, even with a hidden menu — re-checked on
  # v0.7.3: root/wrapper.go still says "always consume the full binding
  # atomically, even when the overlay is hidden".
  #
  # iris-empty-keybindings: an explicit `""` disables a keybinding instead of
  # being replaced by the upstream default (v0.7.3 Load() re-filled
  # `toggle-mode = ""` with ctrl+r, so iris silently ate Ctrl+R).
  #
  # iris-menu-footer: render only the shortcuts that are bound and list the
  # navigate keys too (an empty toggle-mode used to draw a stray "<> Mode").
  #
  # iris-command-prefix-noise: a word that already names a program on PATH is
  # a complete command — the other commands merely sharing its prefix are not
  # what is being typed. `nh` used to offer `nhost` (built-in spec) and
  # `nhlt-dmic-info` (PATH): that menu has nothing to offer, the accept key
  # can execute one of them by accident, and while it is visible the navigate
  # keys never reach the shell's history search (`navigate-closed = "shell"`
  # in files/iris/config.toml, zsh ^P up-line-or-beginning-search). Words that
  # are not commands yet are completed as before.
  #
  # iris-nav-fallthrough: a navigation key is only consumed while the overlay
  # cursor can actually move. At the edge of a visible menu (Ctrl+P on the
  # first item, Ctrl+N on the last) MoveCursor reports no move, and upstream
  # swallowed the key silently — `ds` + Ctrl+P looked dead while the prefix
  # menu (dsh, dsh-statusline, …) was drawn. Now the key falls through to the
  # shell, so up-line-or-beginning-search still recalls the full command; the
  # prefix-noise patch above only covers words that exactly name a PATH command.
  #
  # iris-spec-relevance: the top-level menu only suggests what can actually be
  # run. Upstream registers specs for hundreds of CLIs (and for macOS-only
  # tools); a spec whose program is not on PATH can only end in
  # command-not-found, yet its entries fill every short-prefix menu. Register()
  # now drops macOS-only commands on other systems (dscacheutil, dscl,
  # defaults, launchctl, networksetup, pmset, pkgutil, simctl, codesign,
  # xcode-select/build/xcodeproj/xcodes), and topLevelSuggestions keeps a
  # registry spec only when its binary is on PATH or the word is a shell
  # builtin (cd, exec, source, ...). Subcommand completion for an already
  # typed word is untouched. Tests cover both rules.
  patches = [
    ./iris-select-fallthrough.patch
    ./iris-empty-keybindings.patch
    ./iris-menu-footer.patch
    ./iris-command-prefix-noise.patch
    ./iris-nav-fallthrough.patch
    ./iris-spec-relevance.patch
  ];

  # Tests run: the added spec-relevance tests plus the upstream suite. Two
  # sandbox-environment tests are skipped: TestDetectCached_MidSessionFileCreation
  # relies on directory mtime (overlayfs does not bump it for a file created
  # within the same second), and TestGitSuggestions expects `.git/refs/heads/main`
  # to exist after `git init --initial-branch=main` + commit in the build sandbox
  # (the ref layout differs there). Everything else passes.
  doCheck = true;
  checkFlags = [
    "-skip"
    "TestDetectCached_MidSessionFileCreation|TestGitSuggestions"
  ];

  ldflags = [
    "-s"
    "-w"
    "-X github.com/versenilvis/iris/root.Version=v${version}"
  ];

  meta = lib.mkMeta {
    description = "IRIS (Intelligent Real-time Input Suggestion) — shell auto-completion that works like code editor's IntelliSense";
    homepage = "https://github.com/versenilvis/iris";
    license = lib.licenses.bsd0;
    mainProgram = "iris";
  };
}
