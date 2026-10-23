# Design sources

The app does not build from this folder. These scripts redraw the brand art so that the shipped assets can be
regenerated; the results live in `Sources/Resources/Assets.xcassets` and `Pesto.icon`.

| File | What it does |
|---|---|
| `source/brand-art.py` | Draws the app icons (one per theme), the empty-state pictures and the jar as SVG, renders 1024 px PNGs with `qlmanage`, and with `--catalog` rewrites the asset catalog. Needs macOS and Xcode. |
| `source/mask-icon.swift` | Masks a PNG to the icon's rounded rectangle (called by `brand-art.py`). |
| `source/icon-layers.swift` | Writes the vector layers (`stack`, `front-card`, `letter`, `letter-dark`) used by `Pesto.icon`. The bundle's `icon.json` gives the dark appearance its own ground and a lighter P; clear and tinted are derived from the layers by the system. Look at every appearance with `ictool Pesto.icon --export-image --rendition Dark` (also `Default`, `ClearLight`, `ClearDark`, `TintedLight`, `TintedDark`) from Icon Composer's `Executables` folder. |
| `source/menubar-icon.swift` | Draws the menu-bar template icon at 1x and 2x. |

Never set a Finder icon on the installed app: it writes metadata into the signed bundle and breaks `codesign --verify`.
