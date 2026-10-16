# theme-extract.awk — turn an ImageMagick `txt:` pixel dump into the wallpaper
# palette, one `name=#rrggbb` per line on stdout.
#
#   magick WALL -auto-orient -resize 48x48! -alpha off -depth 8 txt:- \
#     | awk -f theme-extract.awk
#
# Both samplers are ports of the legacy Quickshell code (files/quickshell,
# read-only reference):
#
#   * accent — Helpers/AccentSampler.js sampleAccent(): the mean of the pixels
#     with chroma (max - min) >= 10 and mean brightness 20..235, then a relaxed
#     pass (>= 8, 20..240), then every pixel. The mean is hue-matched the way
#     Helpers/Color.js matchHue(source, "#006FCC") does for Settings/Theme.qml's
#     accentPrimary: the wallpaper's hue, the reference's saturation and
#     lightness (1.0, 0.4).
#
#   * tones — greeter/background/BackgroundImage.qml paintPalette(): weighted
#     k-means (k=4) in Oklab. A pixel weighs 0.25 + saturation * 1.75, the
#     seeds are spread over the lightness range, 16 iterations, the centres are
#     sorted darkest to lightest and the chroma is multiplied by 1.35 (the
#     greeter's posterizeChroma). `coal` is the darkest centre, `surface` the
#     next; `ink` starts at the lightest.
#
# Two honest deviations, both in README.md as well:
#
#   * one 48x48 sample feeds both samplers (the accent grid in Bar.qml is
#     48x48; the greeter's k-means ran on 32x32 — same algorithm, finer grid);
#   * a hue-less mean keeps the QS accent #006FCC: matchHue() would take its
#     hue 0 and paint a grey wallpaper's accent red.
#
# `ink` is readability-clamped: it is pushed from the wallpaper's lightest (or,
# on a light palette, darkest) centre toward white (black) until it contrasts
# with `surface` at WCAG 4.5:1, or reaches the extreme. The secondary text
# (`skin.ink.dim`) is not sampled: theme.plm derives it with `mix()`.

function hexdec(s,   i, c, d, v) {
  v = 0
  for (i = 1; i <= length(s); i++) {
    c = tolower(substr(s, i, 1))
    d = (c >= "0" && c <= "9") ? c + 0 : index("abcdef", c) - 1 + 10
    v = v * 16 + d
  }
  return v
}

function hex(r, g, b) {
  return sprintf("#%02x%02x%02x", int(r + 0.5), int(g + 0.5), int(b + 0.5))
}

function srgb2lin(c) {
  c = c / 255
  return (c <= 0.04045) ? c / 12.92 : ((c + 0.055) / 1.055) ^ 2.4
}

# Linear sRGB back to an 8-bit channel, clamped (BackgroundImage.qml clamps
# the linear value before linearToSrgb; this clamps the result, same ends).
function lin2srgb(c) {
  c = (c <= 0.0031308) ? c * 12.92 : 1.055 * c ^ (1 / 2.4) - 0.055
  if (c < 0) c = 0
  if (c > 1) c = 1
  return c * 255
}

# Oklab forward/inverse, the coefficients of BackgroundImage.qml. The results
# land in OL/OA/OB and CR/CG/OB.
function to_lab(r, g, b,   lr, lg, lb, l, m, s) {
  lr = srgb2lin(r); lg = srgb2lin(g); lb = srgb2lin(b)
  l = (0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb) ^ (1 / 3)
  m = (0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb) ^ (1 / 3)
  s = (0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb) ^ (1 / 3)
  OL = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
  OA = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
  OB = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s
}

function from_lab(L, A, B,   l, m, s) {
  l = (L + 0.3963377774 * A + 0.2158037573 * B) ^ 3
  m = (L - 0.1055613458 * A - 0.0638541728 * B) ^ 3
  s = (L - 0.0894841775 * A - 1.2914855480 * B) ^ 3
  CR = lin2srgb(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s)
  CG = lin2srgb(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s)
  OB = lin2srgb(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
}

# HSL, exactly Helpers/Color.js _rgbToHsl/_hslToRgb (HH/SS and HR/HG/HB out).
function to_hsl(r, g, b,   mx, mn, d, l) {
  r = r / 255; g = g / 255; b = b / 255
  mx = (r > g) ? r : g
  if (b > mx) mx = b
  mn = (r < g) ? r : g
  if (b < mn) mn = b
  l = (mx + mn) / 2
  HH = 0; SS = 0
  if (mx != mn) {
    d = mx - mn
    SS = (l > 0.5) ? d / (2 - mx - mn) : d / (mx + mn)
    if (mx == r) HH = (g - b) / d + ((g < b) ? 6 : 0)
    else if (mx == g) HH = (b - r) / d + 2
    else HH = (r - g) / d + 4
    HH /= 6
  }
}

function hue2rgb(p, q, t) {
  if (t < 0) t += 1
  if (t > 1) t -= 1
  if (t < 1 / 6) return p + (q - p) * 6 * t
  if (t < 1 / 2) return q
  if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
  return p
}

function from_hsl(h, s, l,   q, p) {
  h -= int(h)
  if (h < 0) h += 1
  if (s == 0) {
    HR = l * 255; HG = l * 255; HB = l * 255
    return
  }
  q = (l < 0.5) ? l * (1 + s) : l + s - l * s
  p = 2 * l - q
  HR = hue2rgb(p, q, h + 1 / 3) * 255
  HG = hue2rgb(p, q, h) * 255
  HB = hue2rgb(p, q, h - 1 / 3) * 255
}

# WCAG relative luminance and contrast ratio (Helpers/Color.js _luminance and
# contrastRatio), the readability clamp's metric.
function rel_lum(r, g, b) {
  return 0.2126 * srgb2lin(r) + 0.7152 * srgb2lin(g) + 0.0722 * srgb2lin(b)
}

function contrast(r1, g1, b1, r2, g2, b2,   a, b) {
  a = rel_lum(r1, g1, b1) + 0.05
  b = rel_lum(r2, g2, b2) + 0.05
  return (a > b) ? a / b : b / a
}

# The dump: "x,y: (r,g,b)  #RRGGBB  srgb(r,g,b)"; the header and any line
# without the six hex digits are skipped.
/^[0-9]+,[0-9]+:/ {
  if (split($0, f, "#") < 2) next
  h = substr(f[2], 1, 6)
  if (length(h) != 6) next
  r = hexdec(substr(h, 1, 2))
  g = hexdec(substr(h, 3, 2))
  b = hexdec(substr(h, 5, 2))
  n++
  PR[n] = r; PG[n] = g; PB[n] = b
  mx = (r > g) ? r : g; if (b > mx) mx = b
  mn = (r < g) ? r : g; if (b < mn) mn = b
  lum = (r + g + b) / 3
  if (mx - mn >= 10 && lum >= 20 && lum <= 235) { ars += r; ags += g; abs += b; an++ }
}

END {
  if (n < 8) {
    print "theme-extract: no pixels (is the input an ImageMagick txt: dump?)" > "/dev/stderr"
    exit 1
  }

  # ---- accent: AccentSampler.sampleAccent's two relaxed passes ------------
  if (an == 0) {
    for (i = 1; i <= n; i++) {
      r = PR[i]; g = PG[i]; b = PB[i]
      mx = (r > g) ? r : g; if (b > mx) mx = b
      mn = (r < g) ? r : g; if (b < mn) mn = b
      lum = (r + g + b) / 3
      if (mx - mn >= 8 && lum >= 20 && lum <= 240) { ars += r; ags += g; abs += b; an++ }
    }
  }
  if (an == 0) {
    for (i = 1; i <= n; i++) { ars += PR[i]; ags += PG[i]; abs += PB[i]; an++ }
  }
  aR = ars / an; aG = ags / an; aB = abs / an

  to_hsl(aR, aG, aB)
  if (SS == 0) {
    acR = 0; acG = 0x6f; acB = 0xcc           # colors.accent.primary fallback
  } else {
    from_hsl(HH, 1.0, 0.4)                    # matchHue(mean, "#006FCC")
    acR = HR; acG = HG; acB = HB
  }

  # ---- tones: weighted k-means in Oklab -----------------------------------
  for (i = 1; i <= n; i++) {
    r = PR[i]; g = PG[i]; b = PB[i]
    mx = (r > g) ? r : g; if (b > mx) mx = b
    mn = (r < g) ? r : g; if (b < mn) mn = b
    sat = (mx == 0) ? 0 : (mx - mn) / mx
    W[i] = 0.25 + sat * 1.75
    to_lab(r, g, b)
    L[i] = OL; A[i] = OA; B[i] = OB
  }

  # Seeds are the lightness quantiles BackgroundImage.qml takes after sorting
  # its points; the sort here is over indices, into IX.
  for (i = 1; i <= n; i++) IX[i] = i
  for (i = 2; i <= n; i++) {
    v = IX[i]; lv = L[v]; j = i - 1
    while (j > 0 && L[IX[j]] > lv) { IX[j + 1] = IX[j]; j-- }
    IX[j + 1] = v
  }
  K = 4
  for (c = 1; c <= K; c++) {
    p = IX[int(n * (c - 0.5) / K) + 1]
    CL[c] = L[p]; CA[c] = A[p]; CB[c] = B[p]
  }

  for (it = 0; it < 16; it++) {
    for (c = 1; c <= K; c++) { SL[c] = 0; SA[c] = 0; SB[c] = 0; SW[c] = 0 }
    for (i = 1; i <= n; i++) {
      best = 1; bd = 1e300
      for (c = 1; c <= K; c++) {
        dL = L[i] - CL[c]; dA = A[i] - CA[c]; dB = B[i] - CB[c]
        d = dL * dL + dA * dA + dB * dB
        if (d < bd) { bd = d; best = c }
      }
      SL[best] += L[i] * W[i]
      SA[best] += A[i] * W[i]
      SB[best] += B[i] * W[i]
      SW[best] += W[i]
    }
    for (c = 1; c <= K; c++) {
      if (SW[c] > 0) { CL[c] = SL[c] / SW[c]; CA[c] = SA[c] / SW[c]; CB[c] = SB[c] / SW[c] }
    }
  }

  for (a = 1; a <= K; a++) {
    m = a
    for (c = a + 1; c <= K; c++) if (CL[c] < CL[m]) m = c
    if (m != a) {
      t = CL[a]; CL[a] = CL[m]; CL[m] = t
      t = CA[a]; CA[a] = CA[m]; CA[m] = t
      t = CB[a]; CB[a] = CB[m]; CB[m] = t
    }
  }

  CHROMA = 1.35                               # greeter.posterizeChroma
  from_lab(CL[1], CA[1] * CHROMA, CB[1] * CHROMA); coalR = CR; coalG = CG; coalB = OB
  from_lab(CL[2], CA[2] * CHROMA, CB[2] * CHROMA); surfR = CR; surfG = CG; surfB = OB
  from_lab(CL[K], CA[K] * CHROMA, CB[K] * CHROMA); inkR = CR; inkG = CG; inkB = OB

  # Readability clamp: start from the lightest centre on a dark surface (or the
  # darkest on a light one) and push toward that extreme until 4.5:1 is there.
  rw = contrast(255, 255, 255, surfR, surfG, surfB)
  rb = contrast(0, 0, 0, surfR, surfG, surfB)
  if (rw >= rb) { bR = inkR; bG = inkG; bB = inkB; tR = 255; tG = 255; tB = 255 }
  else { bR = coalR; bG = coalG; bB = coalB; tR = 0; tG = 0; tB = 0 }
  t = 0
  ir = bR; ig = bG; ib = bB
  while (t < 1 && contrast(ir, ig, ib, surfR, surfG, surfB) < 4.5) {
    t += 0.1
    if (t > 1) t = 1
    ir = bR + (tR - bR) * t
    ig = bG + (tG - bG) * t
    ib = bB + (tB - bB) * t
  }

  print "coal=" hex(coalR, coalG, coalB)
  print "surface=" hex(surfR, surfG, surfB)
  print "ink=" hex(ir, ig, ib)
  print "accent=" hex(acR, acG, acB)
}
