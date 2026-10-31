> **ARCHIVED.** Models have been moved to `archive/galgame-assets/`.
> See `public/models/README.md` for restoration notes.

# Assets & attribution

## Background

`backgrounds/kanazawa-night.jpg`

- Title: *Eight Views of Kanazawa at Night* (金沢八景 夜景)
- Artist: Utagawa Hiroshige (歌川広重)
- Collection: Cleveland Museum of Art, 1921.410
- License: **CC0 / Public Domain**
- Source: https://commons.wikimedia.org/wiki/File:Utagawa_Hiroshige_-_Eight_Views_of_Kanazawa_at_Night_-_1921.410_-_Cleveland_Museum_of_Art.tif
- Downloaded as a 1920px JPEG thumbnail from Wikimedia Commons.

## Character models

### PMX (default)

`models/vodyanitsa/Vodyanitsa.pmx` + `models/vodyanitsa/tex/`

- Supplied by the project owner (`Vodyanitsa_MMD_260813`).
- Rights belong to the original creator/rights holder.
- **Not** covered by this repository's license. Do not redistribute without permission.
- 40,933 vertices, 519 bones, 13 materials, 50 morphs.
- `preview.png` comes from the same asset pack.
- 6 textures are referenced by the PMX; the other files in `tex/` are kept for completeness.

### GLB (fallback)

`models/arcore.glb` (copied from `arcore.glb` at the repository root)

- Same character, supplied by the project owner.
- Known to have missing materials/eye issues; kept only as a fallback.
- Rights belong to the original creator/rights holder; **not** covered by this repository's license.

## Fonts

Bundled via Fontsource (SIL Open Font License 1.1):

- Noto Serif SC — https://fonts.google.com/noto/specimen/Noto+Serif+SC
- Noto Sans SC — https://fonts.google.com/noto/specimen/Noto+Sans+SC
- Cormorant Garamond — https://fonts.google.com/specimen/Cormorant+Garamond

## 3D

- three.js — MIT — https://threejs.org
- @moeru/three-mmd — MIT — https://github.com/moeru-ai/three-mmd
  (bundles PMX/VMD parser code derived from babylon-mmd, Apache-2.0)

## TTS

- edge-tts — MIT — https://github.com/rany2/edge-tts
- Voice service: Microsoft Edge online speech. Subject to Microsoft's terms; used here
  as a local prototype. Replace with a self-hosted TTS (Piper, Kokoro, GPT-SoVITS)
  before any public deployment.

## Icons

Inline SVG drawn for this project. No icon-font dependency.
