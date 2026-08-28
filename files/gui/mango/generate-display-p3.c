/* Generate files/gui/mango/Display-P3.icc: D65 white point, DCI-P3
 * primaries, sRGB transfer curve (1024-point sampled decoder table).
 *
 * The ICC parametric 'para' curve cannot be used here: lcms 2.19.1 writes a
 * broken type-3 tag for it (params shifted), which makes cmsCreateTransform
 * fail on the saved profile. A sampled 'curv' tag is unambiguous.
 *
 * Build & run (from repo root):
 *   nix shell nixpkgs#gcc nixpkgs#lcms2 -c bash files/gui/mango/generate-display-p3.sh
 */
#include <lcms2.h>
#include <stdio.h>
#include <stdlib.h>
#include <math.h>

/* sRGB decoder: encoded -> linear (what an ICC TRC tag must hold) */
static double srgb_decode(double x) {
    if (x <= 0.04045) return x / 12.92;
    return pow((x + 0.055) / 1.055, 2.4);
}

int main(int argc, char **argv) {
    if (argc != 2) {
        fprintf(stderr, "usage: %s <output.icc>
", argv[0]);
        return 1;
    }

    cmsCIExyY d65 = { 0.3127, 0.3290, 1.0 };
    cmsCIExyYTRIPLE p3 = {
        { 0.680, 0.320, 1.0 },
        { 0.265, 0.690, 1.0 },
        { 0.150, 0.060, 1.0 },
    };

    cmsUInt16Number table[1024];
    for (int i = 0; i < 1024; i++) {
        double lin = srgb_decode((double)i / 1023.0);
        if (lin < 0) lin = 0;
        if (lin > 1) lin = 1;
        table[i] = (cmsUInt16Number)(lin * 65535.0 + 0.5);
    }
    cmsToneCurve *curve = cmsBuildTabulatedToneCurve16(NULL, 1024, table);
    if (!curve) { fprintf(stderr, "failed to build TRC
"); return 1; }
    cmsToneCurve *curves[3] = { curve, curve, curve };

    cmsHPROFILE profile = cmsCreateRGBProfile(&d65, &p3, curves);
    cmsFreeToneCurve(curve);
    if (!profile) { fprintf(stderr, "failed to create profile
"); return 1; }

    cmsUInt32Number size = 0;
    cmsSaveProfileToMem(profile, NULL, &size);
    cmsUInt8Number *buf = malloc(size);
    if (!cmsSaveProfileToMem(profile, buf, &size)) {
        fprintf(stderr, "failed to save profile
");
        return 1;
    }
    cmsCloseProfile(profile);

    FILE *f = fopen(argv[1], "wb");
    if (!f) { perror(argv[1]); return 1; }
    fwrite(buf, 1, size, f);
    fclose(f);
    free(buf);
    fprintf(stderr, "wrote %s (%u bytes)
", argv[1], (unsigned)size);
    return 0;
}
