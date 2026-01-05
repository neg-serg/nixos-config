commit 9e9ce6a6300317d44333053c3d7634cad18debf4 (HEAD -> master)
Author: Sergey Miroshnichenko <serg.zorg@gmail.com>
Date:   Mon Jan 5 23:26:57 2026 +0300

    [media] enable auto-parallelism for swayimg

diff --git a/packages/overlays/media.nix b/packages/overlays/media.nix
index bd7d53b7..432c4a86 100644
--- a/packages/overlays/media.nix
+++ b/packages/overlays/media.nix
@@ -15,6 +15,9 @@ inputs: _final: prev: let
     inherit (prev) fetchurl;
   };
 in {
+  swayimg = prev.swayimg.overrideAttrs (old: {
+    env.NIX_CFLAGS_COMPILE = toString (old.env.NIX_CFLAGS_COMPILE or "") + " -O3 -ftree-parallelize-loops=8 -floop-parallelize-all";
+  });
   neg = let
     blissify_rs = callPkg (packagesRoot + "/blissify-rs") {};
   in {
