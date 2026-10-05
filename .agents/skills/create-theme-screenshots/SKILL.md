---
name: create-theme-screenshots
description:
  Creates matching dark and light PNG screenshots of Token appearances in real
  Neovim and Ghostty windows on macOS. Use when adding or refreshing README
  gallery images, capturing a newly registered Token appearance, or reproducing
  the established Token screenshot framing and color-management workflow.
---

# Create Token Theme Screenshots

Create only the requested appearance/background pairs. The images are real
Ghostty and Neovim windows; do not synthesize, resize, or generatively alter
them.

## Establish scope

1. Read `AGENTS.md`, `lua/token/appearance.lua`, and the selected appearance's
   palette and appearance modules, its `colors/` entry point, and its
   `contrib/ghostty/<scheme>-dark` and `contrib/ghostty/<scheme>-light` themes.
2. Inspect the destination directory. The script creates or replaces only
   `<scheme>-dark.png` and `<scheme>-light.png` there.
3. Record `git status --short --branch`. Capturing authorizes only the
   requested PNG outputs. Updating `README.md`, uploading images, committing,
   or pushing each needs a separate request.

## Capture

Run the bundled script from the repository root, once per appearance:

```bash
.agents/skills/create-theme-screenshots/scripts/capture.sh \
  <scheme> <destination> [dark|light]...
```

It defaults to both backgrounds and needs `nvim`, ImageMagick (`magick`),
`/Applications/Ghostty.app`, and the MonoLisa and Symbols Nerd Font Mono fonts.
The script:

- copies the fixtures in `assets/` to a temporary directory and runs them with
  `nvim --clean`, so no user configuration, compiled Token cache, LSP client,
  or plugin is loaded;
- validates each background headlessly (colorscheme name, `background`, a
  resolved `Normal` background) and validates each Ghostty theme with
  `ghostty +validate-config` before opening any window;
- launches a separate Ghostty instance per background with the established
  font, window, and color settings, captures its window at native Retina
  resolution with `screencapture -l`, and terminates only that instance;
- converts the capture from the display profile to standard sRGB with a
  color-managed ImageMagick conversion, keeping the alpha channel that holds
  the rounded corners and window shadow;
- fails unless each PNG is 8-bit RGBA sRGB, has only the `IHDR`, `sRGB`,
  `gAMA`, `IDAT`, and `IEND` chunk types, keeps the original alpha
  pixel-for-pixel, and matches the other background's dimensions.

Screen capture needs macOS Screen Recording permission for the terminal that
runs the script. Run it outside any command sandbox: inside one,
`screencapture` fails with `could not create image from display`, even when the
permission is granted.

If the script fails, fix the cause and rerun it. It cleans up its temporary
files and capture process on every exit, and it leaves an earlier final PNG in
place until a new one passes all checks.

## Review the result

The script checks the file format. You still need to check what the images
show. View the dark and light PNGs side by side and confirm:

- the window title reads `<Display Name> · Neovim` and the statusline shows
  `<DISPLAY NAME> · DARK` or `· LIGHT` with `23:9`;
- all 35 source lines are visible without wrapping, and the cursor is on line
  23, column 9 in both images;
- the titlebar and editor background are the same color, for example by
  sampling them:
  `magick <png> -format '%[pixel:p{1000,140}] %[pixel:p{1600,300}]' info:`;
- there are no notifications, private paths, extra tabs, or configuration
  artifacts.

If a published image of the same appearance exists, for example in the README
gallery, compare against it. Small antialiasing differences are expected.
Layout, font, or color differences are not.

## Finish

Report the output paths and dimensions. Confirm that no capture Ghostty
process remains and that `git status --short` differs only by the requested
PNG files, or not at all when the destination is outside the repository.
