#!/usr/bin/env python3
"""Generate the void-and-cluster blue-noise mask used by the greeter's dithering.

The mask is committed (greeter/assets/blue_noise.png) — regenerate it only when
the size or the algorithm changes:

    nix shell nixpkgs#python3Packages.numpy nixpkgs#python3Packages.pillow \\
      -c python3 files/quickshell/scripts/gen_blue_noise.py

Ulichney's void-and-cluster: start from a random half-density pattern, repeatedly
swap the tightest cluster of ones with the largest void, then rank every pixel by
the order in which it is removed/added. Ranks are unique, so the mask is a
permutation of 0..N-1 (a uniform histogram) with the spectrum of blue noise: no
low-frequency clumps, which is what keeps 4-colour dithering free of the visible
cross-hatch that Bayer produces. The Gaussian filter wraps around the edges, so
the tile repeats seamlessly.
"""

from __future__ import annotations

import pathlib
import sys

import numpy as np
from PIL import Image

SIZE = 128
DENSITY = 0.5
SIGMA = 1.9
SEED = 20261006


def gaussian_filter(size: int, sigma: float) -> np.ndarray:
    """Toroidal Gaussian kernel."""
    coordinates = np.arange(size)
    coordinates = np.minimum(coordinates, size - coordinates)
    xx, yy = np.meshgrid(coordinates, coordinates)
    kernel = np.exp(-(xx**2 + yy**2) / (2.0 * sigma**2))
    return kernel / kernel.sum()


def energy(pattern: np.ndarray, kernel: np.ndarray) -> np.ndarray:
    """Density of ones around every pixel (toroidal convolution)."""
    return np.real(np.fft.ifft2(np.fft.fft2(pattern) * np.fft.fft2(kernel)))


def tightest_cluster(
    pattern: np.ndarray, energy_map: np.ndarray
) -> tuple[int, int]:
    masked = np.where(pattern > 0, energy_map, -np.inf)
    return np.unravel_index(np.argmax(masked), pattern.shape)


def largest_void(
    pattern: np.ndarray, energy_map: np.ndarray
) -> tuple[int, int]:
    masked = np.where(pattern <= 0, energy_map, np.inf)
    return np.unravel_index(np.argmin(masked), pattern.shape)


def build_mask(
    size: int = SIZE, sigma: float = SIGMA, seed: int = SEED
) -> np.ndarray:
    rng = np.random.default_rng(seed)
    kernel = gaussian_filter(size, sigma)

    ones = int(round(size * size * DENSITY))
    pattern = np.zeros(size * size, dtype=np.float64)
    pattern[:ones] = 1.0
    rng.shuffle(pattern)
    pattern = pattern.reshape(size, size)

    # Phase 0: settle the half-density pattern — the classic swap loop.
    for _ in range(4000):
        energy_map = energy(pattern, kernel)
        cluster = tightest_cluster(pattern, energy_map)
        void = largest_void(pattern, energy_map)
        if energy_map[cluster] <= energy_map[void]:
            break
        pattern[cluster] = 0.0
        pattern[void] = 1.0

    ranks = np.full((size, size), -1, dtype=np.int64)

    # Phase 1: remove the tightest cluster repeatedly, giving the ones their ranks.
    working = pattern.copy()
    for rank in range(ones - 1, -1, -1):
        energy_map = energy(working, kernel)
        cluster = tightest_cluster(working, energy_map)
        ranks[cluster] = rank
        working[cluster] = 0.0

    # Phase 2: re-add, filling the largest voids with the remaining ranks.
    working = pattern.copy()
    for rank in range(ones, size * size):
        energy_map = energy(working, kernel)
        void = largest_void(working, energy_map)
        ranks[void] = rank
        working[void] = 1.0

    assert (ranks >= 0).all(), "ranks left unassigned"
    return (ranks * (255.0 / (size * size - 1))).round().astype(np.uint8)


def radial_spectrum(mask: np.ndarray) -> tuple[float, float]:
    """Fraction of spectral energy in the low and high frequency bands."""
    spectrum = np.abs(np.fft.fft2(mask.astype(np.float64) - mask.mean())) ** 2
    size = mask.shape[0]
    fy = np.fft.fftfreq(size)[:, None]
    fx = np.fft.fftfreq(size)[None, :]
    radius = np.sqrt(fx**2 + fy**2)
    low = radius < 0.15
    high = radius >= 0.35
    total = spectrum[~np.eye(size, dtype=bool)].sum()
    return spectrum[low].sum() / total, spectrum[high].sum() / total


def main() -> int:
    destination = (
        pathlib.Path(__file__).resolve().parents[1]
        / "greeter/assets/blue_noise.png"
    )
    mask = build_mask()
    low, high = radial_spectrum(mask)
    Image.fromarray(mask, mode="L").save(destination, optimize=True)
    print(
        f"wrote {destination} ({SIZE}x{SIZE}, low-freq energy {low:.3%}, high {high:.3%})"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
