{
  lib,
  neg,
  ...
}:
with lib;
let
  n = neg;
in
{
  imports = [
    ./defaults.nix
    ./surfingkeys-server.nix
  ];

  config = lib.mkMerge [
    (n.mkHomeFiles {
      ".config/surfingkeys.js".text = ''
        settings.theme = `
        :root {
          --sk-main: #89cdd2;
          --sk-main-weak: #0a3749;
          --sk-bg: #020202;
          --sk-off-bg: #0a0a0a;
          --sk-bg-weak: #0f1419;
        }

        body {
          background-color: var(--sk-bg);
        }

        .sk_theme {
          font-family: Iosevka;
          font-size: 15px;
          background-color: var(--sk-bg);
          color: var(--sk-main);
          border: 2px solid #0a3749;
          border-radius: 0;
        }

        .sk_theme tbody {
          color: var(--sk-main);
        }

        .sk_theme input {
          color: var(--sk-main);
          background-color: var(--sk-bg);
          border: 1px solid #0a3749;
          border-radius: 0;
          padding: 4px 8px;
        }

        .sk_theme .url {
          color: var(--sk-main-weak);
        }

        .sk_theme .annotation {
          color: var(--sk-main-weak);
        }

        .sk_theme .focused {
          background-color: #0b2536;
          color: var(--sk-main);
        }
        `

        settings.hintAlign = "left"
        settings.hintsThreshold = 100
        settings.scrollStepSize = 70
        settings.smoothScroll = true

        map('t', 'T')
        mapkey('t', 'Open URL', function() {
          Front.openOmnibar({type: "URLs", extra: "address"})
        });

        map('j', 'e')
        map('k', 'd')
        map('u', 'S')
        map('w', 'E')
        map('h', 'R')
        map('l', 'L')

        mapkey('e', 'scroll half page down', function() { Normal.scroll("pageDown") });
        mapkey('d', 'scroll half page up', function() { Normal.scroll("pageUp") });

        mapkey('S', 'Go back', function() { history.back() });
        mapkey('E', 'Go forward', function() { history.forward() });

        mapkey('R', 'Go one tab left', function() { RUNTIME('previousTab') });
        mapkey('L', 'Go one tab right', function() { RUNTIME('nextTab') });

        mapkey('b', 'scroll full page down', function() { Normal.scroll("fullPageDown") });
        mapkey('v', 'scroll full page up', function() { Normal.scroll("fullPageUp") });

        mapkey('[', 'Decrease playback rate', function() {
          var video = document.querySelector('video');
          if (video) {
            video.playbackRate = Math.max(0.25, video.playbackRate - 0.25);
          }
        });

        mapkey(']', 'Increase playback rate', function() {
          var video = document.querySelector('video');
          if (video) {
            video.playbackRate = Math.min(16, video.playbackRate + 0.25);
          }
        });

        mapkey('zi', 'Download image', function() {
          var url = window.getSelection().toString().trim();
          if (!url) {
            var el = document.activeElement;
            if (el && el.tagName === 'IMG') url = el.src;
          }
          if (url) {
            Front.downloadUrl(url);
          }
        });

        api.addQuickMark('m', 'https://mail.google.com/mail/u/0/#inbox');
        api.addQuickMark('c', 'https://calendar.google.com/calendar/u/0/r');
        api.addQuickMark('d', 'https://drive.google.com/drive/u/0/my-drive');
        api.addQuickMark('t', 'https://translate.google.com/');
        api.addQuickMark('g', 'https://github.com/');
        api.addQuickMark('y', 'https://www.youtube.com/');
        api.addQuickMark('r', 'https://www.reddit.com/');
        api.addQuickMark('a', 'https://archlinux.org/');
        api.addQuickMark('w', 'https://en.wikipedia.org/');
        api.addQuickMark('x', 'https://x.com/');
        api.addQuickMark('p', 'https://www.perplexity.ai/');
        api.addQuickMark('n', 'https://nixos.wiki/');
        api.addQuickMark('s', 'https://search.nixos.org/packages');
        api.addQuickMark('h', 'https://github.com/neg-serg');

        addSearchAlias('g', 'google', 'https://www.google.com/search?q=');
        addSearchAlias('y', 'youtube', 'https://www.youtube.com/results?search_query=');
        addSearchAlias('w', 'wikipedia', 'https://en.wikipedia.org/wiki/');
        addSearchAlias('n', 'nixpkgs', 'https://search.nixos.org/packages?query=');
        addSearchAlias('a', 'archwiki', 'https://wiki.archlinux.org/index.php/');
        addSearchAlias('r', 'reddit', 'https://www.reddit.com/search/?q=');
        addSearchAlias('g', 'github', 'https://github.com/search?q=');
        addSearchAlias('t', 'translate', 'https://translate.google.com/?sl=auto&tl=auto&text=');
      '';
    })
  ];
}
