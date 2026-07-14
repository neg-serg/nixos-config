---
name: color
description: "Color space conversion between HEX, RGB, HSL, CMYK formats using CLI and bash"
---

# Color Conversion

Use bash arithmetic and common tools instead of MCP color-convert server.

## HEX ↔ RGB

```bash
# HEX to RGB
hex="FF5733"
r=$((16#${hex:0:2}))
g=$((16#${hex:2:2}))
b=$((16#${hex:4:2}))
echo "RGB: $r, $g, $b"

# RGB to HEX
r=255; g=87; b=51
printf "#%02X%02X%02X\n" $r $g $b
```

## RGB ↔ HSL

Use Python:

```python
python3 -c "
import colorsys
r,g,b = 255/255, 87/255, 51/255
h,l,s = colorsys.rgb_to_hls(r,g,b)
print(f'HSL: {h*360:.0f}°, {s*100:.0f}%, {l*100:.0f}%')
"
```

## Color Palette Generation

### From an image (using ImageMagick)

```bash
convert image.png -colors 5 -unique-colors txt:- | tail -n +2
```

### Terminal-safe palette

```bash
for code in {0..255}; do
  printf "\033[48;5;%sm %3d \033[0m" "$code" "$code"
  (( (code+1) % 16 == 0 )) && echo
done
```

## Color Manipulation

```bash
# Lighten (increase brightness in HSL)
python3 -c "
import colorsys
h,s,l = 0.1, 0.8, 0.5
l = min(1.0, l * 1.2)
r,g,b = colorsys.hls_to_rgb(h,l,s)
print(f'#{int(r*255):02X}{int(g*255):02X}{int(b*255):02X}')
"
```

## CSS Named Colors

```bash
# Convert CSS name to hex
python3 -c "import matplotlib.colors as mc; print(mc.to_hex('tomato'))"
python3 -c "import matplotlib.colors as mc; print(mc.to_rgba('skyblue'))"
```
