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
          set line-number-interval = 1
          set tab-size = 4
          set horizontal-scroll = 50%
          set split-view-height = 66%
          set vertical-split = auto
          set mouse = true
          set mouse-wheel-cursor = true
          set blame-options = -C -C -C
          set show-rev-graph = true
          set main-view = date:default author:full commit-title:yes id:yes line-number:yes interval=1 graph:yes refs:yes overflow=no
          set main-view-commit-title-graph = no-commit-title-graph
          set main-view-commit-title-overflow = trim
          set grep-use-vi-mode = yes
          set grep-line-numbers = yes

          bind generic <Down> next
          bind generic <Up> previous
          bind generic j next
          bind generic k previous
          bind generic J move-half-page-down
          bind generic K move-half-page-up
          bind generic <C-d> move-page-down
          bind generic <C-u> move-page-up
          bind generic <Home> move-first-line
          bind generic <End> move-last-line

          bind generic / search
          bind generic ? search-back

          bind generic n find-next
          bind generic N find-prev

          bind generic e !gd -y -- %(file) %(lineno)
          bind generic E !gd %(file)

          bind generic <C-l> screen-redraw

          bind generic <F5> reload

          bind generic <Space> view-close

          bind diff @ :toggle diff-context -u999999

          bind main C :toggle commit-title-graph
          bind main <C-b> :toggle commit-title-overflow

          bind tree H :toggle show-hidden-files

          bind status u :toggle untracked-dir-content

          bind stage u :toggle status

          bind generic | :toggle vertical-split

          bind status g :toggle file-filter-regexp

          set main-view-columns = \
          	author \
          	commit-title \
          	date \
          	line-number

          set blame-view-columns = \
          	author:width=14 \
          	date:width=9 \
          	file-name:show=False \
          	id:yes,color \
          	line-number:interval=1:width=6 \
          	text

          set blob-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set branch-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set grep-view-columns = \
          	file-name:width=60 \
          	text

          set log-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set pager-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set refs-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set stage-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set stash-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set status-view-columns = \
          	file-name:width=80 \
          	text

          set tree-view-columns = \
          	line-number:interval=1:width=6 \
          	text

          set color "date"			blue	default
          set color "author"			cyan	default
          set color "filename"			yellow	default
          set color "diff_marker"		green	default
          set color "diff_header"		magenta	default
          set color "commit"			green	default
          set color "diff_add"			green	default
          set color "diff_add2"			green	default
          set color "diff_del"			red	default
          set color "diff_del2"			red	default
          set color "diff_misc"			blue	default
          set color "graphics"			blue	default
          set color "mode_change"		yellow	default
          set color "report-description"	blue	default

          set color "main-local-tag"		yellow	default	bold
          set color "main-remote-tag"		yellow	default
          set color "main-replace-tag"		yellow	default

          color "header"			white	default
          color "line-number"			blue	default
          color "id"				yellow	default
          color "delimiter"			blue	default
          color "date"				blue	default
          color "mode"				yellow	default
          color "overflow"			yellow	default
          color "section"			white	default
          color "directory"			white	default
          color "file"				white	default
          color "file-size"			default	default
          color "ref"				cyan	default
          color "remote-ref"			cyan	default
          color "tag"				yellow	default
          color "status"			yellow	default
          color "help-group"			white	default
          color "help-action"			default	default
          color "diff-stat"			blue	default
          color "palette-0"			black	default
          color "palette-1"			red	default
          color "palette-2"			green	default
          color "palette-3"			yellow	default
          color "palette-4"			blue	default
          color "palette-5"			magenta	default
          color "palette-6"			cyan	default
          color "palette-7"			white	default
          color "palette-8"			default	default
          color "palette-9"			red	default	bold
          color "palette-10"			green	default	bold
          color "palette-11"			yellow	default	bold
          color "palette-12"			blue	default	bold
          color "palette-13"			magenta	default	bold
          color "palette-14"			cyan	default	bold
          color "palette-15"			white	default	bold

          color main-commit		green	default
          color main-head		cyan	default	bold
          color main-remote		yellow	default
          color main-tracked		yellow	default	bold
          color main-ref		cyan	default
          color tree-head		default	default	bold
          color tree-dir		yellow	default
          color tree-file		default	default
          color stat-none		default	default
          color stat-staged		default	default
          color stat-untracked		default	default
          color stat-unstaged		default	default
          color blame-id		magenta	default
          color graph-commit		blue	default
        '';
      })
    ]
  );
}
