#!/usr/bin/env bash
# Capture Token theme screenshots in real Ghostty and Neovim windows, convert
# them to standard sRGB, and check the mechanical PNG requirements.
#
# Usage: capture.sh <scheme> <output-dir> [dark|light]...
# Writes <output-dir>/<scheme>-<background>.png for each background (default:
# dark and light) and replaces only those files.

set -euo pipefail

readonly ghostty_app=/Applications/Ghostty.app
readonly ghostty_bin=$ghostty_app/Contents/MacOS/ghostty
readonly srgb_profile='/System/Library/ColorSync/Profiles/sRGB Profile.icc'
readonly expected_chunks='IHDR sRGB gAMA IDAT IEND'
# Neovim sets the cursor 100 ms after VimEnter; leave room for the first draw.
readonly settle_seconds=2

die() {
  printf 'capture: %s\n' "$*" >&2
  exit 1
}

(($# >= 2)) || die 'usage: capture.sh <scheme> <output-dir> [dark|light]...'
scheme=$1
output_dir=$2
shift 2
backgrounds=("$@")
((${#backgrounds[@]})) || backgrounds=(dark light)

skill_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
repo=$(git -C "$skill_dir" rev-parse --show-toplevel)
nvim_bin=$(command -v nvim) || die 'nvim not found'
command -v magick >/dev/null || die 'ImageMagick (magick) not found'
[[ -x $ghostty_bin ]] || die "Ghostty not found at $ghostty_app"
[[ -d $output_dir ]] || die "output directory does not exist: $output_dir"
output_dir=$(cd "$output_dir" && pwd)
[[ -f $repo/colors/$scheme.lua ]] || die "unknown colorscheme: $scheme"

for background in "${backgrounds[@]}"; do
  [[ $background == dark || $background == light ]] ||
    die "unexpected background: $background"
  [[ -f $repo/contrib/ghostty/$scheme-$background ]] ||
    die "missing Ghostty theme: contrib/ghostty/$scheme-$background"
done

work=$(mktemp -d)
staged=()
# Every capture instance carries the unique work directory in its command line,
# so cleanup can stop it even if the script fails before finding its PID.
cleanup() {
  pkill -f "^$ghostty_bin .*$work/init.lua" 2>/dev/null || true
  rm -f "${staged[@]}"
  rm -rf "$work"
}
trap cleanup EXIT

# Ghostty's direct: command splits on whitespace, so every path it receives
# must be free of it.
for path in "$repo" "$work" "$nvim_bin"; do
  [[ $path != *[[:space:]]* ]] || die "path contains whitespace: $path"
done

cp "$skill_dir/assets/init.lua" "$skill_dir/assets/signal_garden.lua" "$work/"

display_name=$(
  "$nvim_bin" --clean --headless --cmd "set runtimepath^=$repo" \
    -c "lua io.stdout:write(require('token.appearance').get('$scheme').display_name)" \
    -c 'qa!'
)
[[ -n $display_name ]] || die "no display name registered for $scheme"

# Validate every requested background before opening any window.
for background in "${backgrounds[@]}"; do
  env TOKEN_CAPTURE_REPO="$repo" TOKEN_CAPTURE_SCHEME="$scheme" \
    TOKEN_CAPTURE_BACKGROUND="$background" "$nvim_bin" --clean --headless -u "$work/init.lua" \
    "$work/signal_garden.lua" \
    -c "lua local ok = vim.g.colors_name == '$scheme' and vim.o.background == '$background'
      and vim.api.nvim_get_hl(0, { name = 'Normal' }).bg ~= nil
      if not ok then io.stderr:write('headless check failed\n') vim.cmd.cquit() end" \
    -c 'qa!' || die "headless check failed for $scheme $background"
  "$ghostty_bin" +validate-config \
    --config-file="$repo/contrib/ghostty/$scheme-$background" ||
    die "Ghostty rejected contrib/ghostty/$scheme-$background"
done

# Prints the on-screen layer-zero window number for a PID, or nothing.
window_id() {
  osascript -l JavaScript -e '
    ObjC.import("CoreGraphics");
    function run(argv) {
      const pid = Number(argv[0]);
      const info = ObjC.deepUnwrap(ObjC.castRefToObject(
        $.CGWindowListCopyWindowInfo($.kCGWindowListOptionOnScreenOnly, $.kCGNullWindowID)));
      const win = info.find(w => w.kCGWindowOwnerPID === pid && w.kCGWindowLayer === 0);
      return win ? String(win.kCGWindowNumber) : "";
    }' "$1"
}

capture() {
  local background=$1 grade pid wid raw srgb
  [[ $background == dark ]] && grade=-15 || grade=15
  raw=$work/$background-raw.png
  srgb=$work/$background.png

  open -na "$ghostty_app" --args \
    --config-default-files=false \
    --theme="$repo/contrib/ghostty/$scheme-$background" \
    --title="$display_name · Neovim" \
    --font-family=MonoLisaCode \
    '--font-family=Symbols Nerd Font Mono' \
    --font-size=13 \
    --font-synthetic-style=false \
    --font-variation=wght=450 \
    --font-variation=GRAD="$grade" \
    --font-variation-bold=wght=700 \
    --font-variation-bold=GRAD="$grade" \
    --font-variation-italic=wght=450 \
    --font-variation-italic=GRAD="$grade" \
    --font-variation-bold-italic=wght=700 \
    --font-variation-bold-italic=GRAD="$grade" \
    --font-feature=+calt,+cv01,+cv02,+cv03,+cv04,+cv05,+cv06,-cv07,-cv08 \
    --font-feature=+cv09,+cv10,+cv11,+cv12,+dlig,+liga,+ss01 \
    --font-feature=-ss02,-ss03,-ss04,-ss05,-ss06,-ss07,-ss08 \
    --font-feature=-ss09,-ss10,-ss11,-ss12,+ss13,-ss14,-ss15,-zero \
    --window-title-font-family=MonoLisaText \
    --window-width=96 \
    --window-height=35 \
    --window-save-state=never \
    --window-padding-x=14 \
    --window-padding-y=14 \
    --window-padding-balance=true \
    --background-opacity=1 \
    --window-colorspace=srgb \
    --macos-titlebar-style=transparent \
    --shell-integration=none \
    --cursor-style=block \
    --cursor-style-blink=false \
    --initial-command="direct:/usr/bin/env TOKEN_CAPTURE_REPO=$repo TOKEN_CAPTURE_SCHEME=$scheme TOKEN_CAPTURE_BACKGROUND=$background $nvim_bin --clean -u $work/init.lua $work/signal_garden.lua"

  # Match this background's instance by its unique initial command.
  for _ in {1..50}; do
    pid=$(pgrep -f "^$ghostty_bin .*TOKEN_CAPTURE_BACKGROUND=$background .*$work/init.lua" || true)
    [[ -n $pid ]] && break
    sleep 0.2
  done
  [[ -n $pid && $pid != *$'\n'* ]] || die "expected one capture Ghostty process, got: ${pid:-none}"

  # The process can exist briefly before its window does.
  wid=
  for _ in {1..50}; do
    wid=$(window_id "$pid")
    [[ $wid =~ ^[1-9][0-9]*$ ]] && break
    wid=
    sleep 0.2
  done
  [[ -n $wid ]] || die "no window appeared for Ghostty PID $pid"
  sleep "$settle_seconds"

  /usr/sbin/screencapture -l"$wid" -x -t png "$raw"
  # The instance may already have exited on its own.
  kill "$pid" 2>/dev/null || true
  for _ in {1..25}; do
    kill -0 "$pid" 2>/dev/null || break
    sleep 0.2
  done
  ! kill -0 "$pid" 2>/dev/null || die "Ghostty PID $pid did not exit"

  # Color-managed conversion from the display profile; never -normalize.
  magick "$raw" -profile "$srgb_profile" \
    -define png:color-type=6 \
    -define png:exclude-chunk=date,time,pHYs,bKGD,tEXt,zTXt,iTXt,eXIf,cICP \
    "$srgb"

  local format alpha_diff chunks
  format=$(magick identify -format '%z %[channels] %[colorspace]' "$srgb")
  [[ $format == '8 srgba 4.0 sRGB' ]] || die "$background: unexpected format: $format"
  alpha_diff=$(magick compare -metric AE \
    <(magick "$raw" -alpha extract -strip png:-) <(magick "$srgb" -alpha extract -strip png:-) \
    null: 2>&1 || true)
  [[ $alpha_diff == 0 || $alpha_diff == '0 (0)' ]] ||
    die "$background: conversion changed alpha ($alpha_diff)"
  chunks=$(png_chunks "$srgb")
  [[ $chunks == "$expected_chunks" ]] || die "$background: unexpected PNG chunks: $chunks"
}

# Prints the distinct chunk types of a PNG in file order.
png_chunks() {
  local file=$1 offset=8 size length
  size=$(stat -f %z "$file")
  while ((offset < size)); do
    length=$(od -An -tu1 -j "$offset" -N4 "$file" |
      awk 'NF { print $1 * 16777216 + $2 * 65536 + $3 * 256 + $4 }')
    dd if="$file" bs=1 skip=$((offset + 4)) count=4 2>/dev/null
    printf '\n'
    offset=$((offset + 12 + length))
  done | uniq | paste -sd ' ' -
}

for background in "${backgrounds[@]}"; do
  capture "$background"
done

if ((${#backgrounds[@]} == 2)); then
  sizes=$(magick identify -format '%wx%h\n' "$work/dark.png" "$work/light.png" | sort -u | wc -l)
  ((sizes == 1)) || die 'dark and light captures have different dimensions'
fi

# Replace outputs only after every capture passed. Staging beside the
# destination keeps each final rename atomic.
for background in "${backgrounds[@]}"; do
  stage=$output_dir/.$scheme-$background.png.$$
  staged+=("$stage")
  cp "$work/$background.png" "$stage"
done
for background in "${backgrounds[@]}"; do
  final=$output_dir/$scheme-$background.png
  mv -f "$output_dir/.$scheme-$background.png.$$" "$final"
  printf '%s %s\n' "$final" "$(magick identify -format '%wx%h' "$final")"
done
