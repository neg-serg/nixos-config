{
  config,
  lib,
  pkgs,
  neg,
  impurity ? null,
  ...
}:
let
  n = neg impurity;
  cfg = config.features.dev;
in
{
  config = lib.mkIf (cfg.enable or false) (
    lib.mkMerge [
      {
        environment.systemPackages = [ pkgs.tig ]; # Text-mode interface for git
      }
      (n.mkHomeFiles {
        ".config/tig/config".text = ''
          set show-changes = true
          set tab-size = 4
          set horizontal-scroll = 50%
          set split-view-height = 66%
          set vertical-split = auto
          set mouse = true
          set mouse-wheel-cursor = true
          set blame-options = -C -C -C
          set main-view-commit-title-graph = no
          set main-view-commit-title-overflow = trim

          bind generic <Down> next
          bind generic <Up> previous
          bind generic j next
          bind generic k previous
          bind generic <Home> move-first-line
          bind generic <End> move-last-line

          bind generic / search
          bind generic ? search-back

          bind generic n find-next
          bind generic N find-prev

          bind generic e !gd -y -- %(file) %(lineno)
          bind generic E !gd %(file)

          bind generic <F5> :reload

          bind diff @ :toggle diff-context -u999999

          bind main C :toggle commit-title-graph
          bind main <C-b> :toggle commit-title-overflow

          bind tree H :toggle show-hidden-files

          bind status u :toggle untracked-dir-content

          bind stage u :toggle status

          bind generic | :toggle vertical-split

          bind status g :toggle file-filter-regexp

          set main-view = \
          	author:width=14 \
          	date:default \
          	id:yes,color \
          	line-number:yes,interval=1 \
          	commit-title:yes,overflow=trim

          set blame-view = \
          	author:width=14 \
          	date:width=9 \
          	file-name:no \
          	id:yes,color \
          	line-number:yes,interval=1,width=6 \
          	text

          set blob-view = \
          	line-number:yes,interval=1,width=6 \
          	text

          set grep-view = \
          	file-name:width=60 \
          	text

          set log-view = \
          	line-number:yes,interval=1,width=6 \
          	text

          set pager-view = \
          	line-number:yes,interval=1,width=6 \
          	text

          set refs-view = \
          	author:width=14 \
          	date:default \
          	id:yes,color \
          	line-number:yes,interval=1 \
          	commit-title:yes

          set stage-view = \
          	line-number:yes,interval=1,width=6 \
          	text

          set stash-view = \
          	author:width=14 \
          	date:default \
          	id:yes,color \
          	line-number:yes,interval=1 \
          	commit-title:yes

          set status-view = \
          	file-name:width=80 \
          	line-number:yes,interval=1 \
          	status

          set tree-view = \
          	file-name:width=60 \
          	line-number:yes,interval=1 \
          	mode \
          	file-size

          color date			blue	default
          color author			cyan	default
          color diff-header		magenta	default
          color diff-add			green	default
          color diff-add2		green	default
          color diff-del			red	default
          color diff-del2			red	default
          color header			white	default
          color line-number		blue	default
          color id			yellow	default
          color delimiter		blue	default
          color mode			yellow	default
          color overflow		yellow	default
          color section			white	default
          color directory		white	default
          color file			white	default
          color file-size		default	default
          color status			yellow	default
          color help-group		white	default
          color help-action		default	default
          color diff-stat		blue	default

          color main-commit		green	default
          color main-head		cyan	default	bold
          color main-remote		yellow	default
          color main-tracked		yellow	default	bold
          color main-ref		cyan	default
          color tree.header		default	default	bold
          color tree.directory		yellow	default
          color tree.file		default	default
          color stat-none		default	default
          color stat-staged		default	default
          color stat-untracked		default	default
          color stat-unstaged		default	default
          color graph-commit		blue	default
        '';
      })
    ]
  );
}
