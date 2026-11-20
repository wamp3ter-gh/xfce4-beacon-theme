#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Wampeter Foma
#
# previews.sh: the README's button sheets, rendered into screenshots/.
#
# Usage:
#   ./previews.sh
#
# What it does:
#   - copies the tracked files (git ls-files) into a private work folder
#   - builds preview themes there from the shipped colours and glyph sets
#   - tiles the generated button images at 2x, pixel for pixel
#   - leaves build/ untouched
#
# Needs:
#   - a git checkout, not a downloaded archive
#   - the build tools (build.sh checks them)
#   - git, xargs
#   - ImageMagick: convert, montage
#
# Writes:
#   - screenshots/shapes.png: bare, disc and ring buttons in every state, dark and light
#   - screenshots/glyphs.png: glyph sets a, b and c, every button, normal and toggled
set -euo pipefail

# the extra tools for the sheets; build.sh checks its own
missing=()
for c in git xargs convert montage; do command -v "$c" >/dev/null || missing+=("$c"); done
[ ${#missing[@]} -eq 0 ] || {
	echo "previews.sh: missing tools: ${missing[*]} (Debian/Ubuntu: git findutils imagemagick)" >&2
	exit 1
}

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
OUT=$ROOT/screenshots
WORK=$ROOT/build.previews
BG='#2b3d4a'
INK='#f0f0e8'
rm -rf "$WORK"
mkdir -p "$WORK/repo" "$OUT"
git -C "$ROOT" ls-files -z | (cd "$ROOT" && xargs -0 cp --parents -t "$WORK/repo")
# the shipped colours and glyph sets, with preview themes in place of the shipped ones
{
	grep -v '^theme ' "$ROOT/beacon.conf"
	echo 'theme p-{shape}-dark colour=steel shape=bare,disc,ring'
	echo 'theme p-{shape}-light colour=steel-light tone=light shape=bare,disc,ring'
	echo 'theme p-g{glyphs} colour=steel glyphs=a,b,c'
} >"$WORK/preview.conf"
"$WORK/repo/build.sh" "$WORK/preview.conf" >/dev/null
B=$WORK/repo/build

# tile <in> <out>: a button image at 2x, pixel for pixel.
# It is centred on a tile wide enough for its label.
tile() { convert "$1" -filter point -resize 200% -background "$BG" -gravity center -extent 120x64 "$2"; }

# shapes: one row per shape and tone; maximize in every state, then close
STATES="active prelight pressed toggled-active inactive"
rows=()
for s in bare-dark disc-dark ring-dark bare-light disc-light ring-light; do
	args=()
	for st in $STATES; do
		f=maximize-$st
		[ "${st%%-*}" = toggled ] && f=maximize-toggled-${st#toggled-}
		tile "$B/p-$s/xfwm4/$f.png" "$WORK/$s-$st.png"
		args+=(-label "$st" "$WORK/$s-$st.png")
	done
	for st in active prelight pressed; do
		tile "$B/p-$s/xfwm4/close-$st.png" "$WORK/$s-close-$st.png"
		args+=(-label "close $st" "$WORK/$s-close-$st.png")
	done
	montage "${args[@]}" -tile x1 -geometry +6+4 -pointsize 12 -background "$BG" -fill "$INK" "$WORK/row-$s.png"
	rows+=(-label "shape=${s%-*} tone=${s#*-}" "$WORK/row-$s.png")
done
montage "${rows[@]}" -tile 1x -geometry +0+8 -pointsize 15 -background "$BG" -fill "$INK" "$OUT/shapes.png"

# glyphs: one row per set; every button, toggled ones beside their normal state
BUTTONS="menu stick stick-toggled shade shade-toggled hide maximize maximize-toggled close"
rows=()
for g in a b c; do
	args=()
	for b in $BUTTONS; do
		tile "$B/p-g$g/xfwm4/$b-active.png" "$WORK/g$g-$b.png"
		args+=(-label "$b" "$WORK/g$g-$b.png")
	done
	montage "${args[@]}" -tile x1 -geometry +6+4 -pointsize 12 -background "$BG" -fill "$INK" "$WORK/row-g$g.png"
	rows+=(-label "glyphs=$g" "$WORK/row-g$g.png")
done
montage "${rows[@]}" -tile 1x -geometry +0+8 -pointsize 15 -background "$BG" -fill "$INK" "$OUT/glyphs.png"

rm -rf "$WORK"
ls "$OUT"
