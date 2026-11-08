# Wallpaper artwork and provenance

The seven wallpapers are flat poster-press compositions rendered by
`scripts/build-wallpapers` from the SUBCULT brand kit in `theme/brand/`. They
use only the approved SUBCULT marks, the brand palette (violet `#8b5cf6`, ink
`#100b19`, acid `#00ff88`, paper `#f0ece4`), and the bundled Oswald and
JetBrains Mono fonts. No photographs, generated imagery, or third-party artwork
are included.

| File | Pixels | SHA-256 | Composition |
|---|---:|---|---|
| `backgrounds/1-subcult-press.png` | 2560×1440 | `b028e2441a06a38e518bde0a5c059dc85a6863aed326e8c384347c59e3c10f14` | White SC_ mark with outlined acid block on ink, violet edge bar |
| `backgrounds/2-subcult-violet.png` | 2560×1440 | `8ccb811cdc91a3596d9130c644127687fca9b093e5d1e1d85737978527466345` | SUBCULT wordmark in ink on a violet field, acid registration block |
| `backgrounds/3-subcult-archive.png` | 2560×1440 | `c396cd823f63dd36638663039296c235d0de9a88fdd80e4d3212f8c833e1e37e` | Violet halftone ramp behind the white SC_ mark on ink |
| `backgrounds/4-subcult-signal.png` | 2560×1440 | `fbf4ff372771d79f2f31cd4eb723d30fce61b7834d07c22579b5a8ac5a79f486` | Acid SIGNAL headline between hazard stripes; used by the intrusion drill |
| `backgrounds/5-subcult-acid.png` | 2560×1440 | `08f8bb5b2c1ca24930e4b835b64c12c924e412b0df6adb776744dc362eb5e500` | Ink SC_ mark on a tilted acid block over ink |
| `backgrounds/6-subcult-paper.png` | 2560×1440 | `f444b4465bf7251626c024846b63d22729f945a26a151866e10722b4a66e7e9d` | Ink SC_ mark on a tilted violet block over paper |
| `backgrounds/7-subcult-ink.png` | 2560×1440 | `ad32d43492b00488fbf6b940edc8c2d3bbed9445625b8a6f25d5b12b4316e37c` | White SC_ mark inside a violet outline block on near-black |

## Rebuilding

```bash
scripts/build-wallpapers
(cd theme && sha256sum backgrounds/*.png > backgrounds.sha256)
```

The script renders through `rsvg-convert` with a private fontconfig file that
points at `theme/brand/fonts/`, so it installs nothing. Marks are inlined from
the outlined SVGs without redrawing, stretching, or added effects, as the brand
guide requires. Rendered bytes can differ between librsvg and FreeType builds;
review the images and update the hashes together.

The hashes above are duplicated in `backgrounds.sha256` for automated
validation. From this directory, run `sha256sum --check backgrounds.sha256` to
detect later replacements.
