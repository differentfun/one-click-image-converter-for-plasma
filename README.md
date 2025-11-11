# One-click Image Converter for Plasma

This repository ships a tiny installer that adds “Convert to PNG/JPEG” entries to Dolphin’s right-click menu. The actions rely on ImageMagick (`magick`/`convert`) and work on both Plasma 5 and Plasma 6.

## Requirements

- KDE Plasma with Dolphin/KIO service menus enabled.
- ImageMagick (`sudo apt install imagemagick` on Debian-based systems).

## Installation

```bash
chmod +x install-service-menu.sh          # first run only
./install-service-menu.sh                 # adds the service menu
```

Useful flags:

- `--force` – overwrite an existing `one-click-image-converter.desktop`.
- `--plasma5` / `--plasma6` – force a specific service menu directory.
- `--target-dir <path>` – write the desktop file to a custom location.

Without flags the script inspects `plasmashell --version` and installs into the matching Plasma 5 or Plasma 6 service-menu directory automatically.

During installation a helper binary `~/.local/bin/one-click-image-converter` is (re)created; the service menu calls this script to handle loops, collision handling, and JPEG quality settings. The installer also toggles `shell_access=true` in `~/.config/kdeglobals` (using `kwriteconfig6/5`) so Plasma allows service menus to launch local shell commands—a requirement introduced in Plasma 6.

The installer restarts Dolphin automatically so the new **One-click Conversion** submenu is available right away (restart manually only if the script reports a failure).

## What gets installed

The installer writes `one-click-image-converter.desktop` into:

- `~/.local/share/kservices5/ServiceMenus` on Plasma 5.
- `~/.local/share/kio/servicemenus` on Plasma 6.

KDE requires user-provided service menus to be marked as executable, so the installer sets mode `0755` on the `.desktop` file it writes.

The menu registers against `image/*` plus a pile of explicit MIME types (HEIC/HEIF, AVIF, SVG, ICO, TGA, PNM/PGM/PPM, etc.) so it shows up for most image formats Dolphin understands.

Each action loops over the selected files via the helper script, creates the converted file next to the original, and auto-resolves name collisions by appending ` (1)`, ` (2)`, etc. Defaults:

- PNG – no extra flags (lossless by definition).
- JPEG – `-quality 92`.
- WebP – `-quality 90`.

Tweak `~/.local/bin/one-click-image-converter` if you prefer other defaults.

To remove the feature, delete the generated `.desktop` file and restart Dolphin.
