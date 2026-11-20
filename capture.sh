#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Wampeter Foma
#
# capture.sh: real xfwm4 screenshots of every built theme, into screenshots/.
#
# Usage:
#   ./capture.sh
#
# Run it on a running Xfce (xfwm4) desktop, after ./build.sh <config>.
#
# What it does:
#   - installs the themes (./install.sh)
#   - opens three xterms: a plain backdrop and two windows, one of them focused
#   - switches xfwm4 through every theme and shoots each one
#   - shoots dark themes on a dark backdrop, with dark windows
#   - shoots light themes on a light backdrop, with light windows
#   - sorts themes by the tone build.sh records in each themerc
#   - holds xfwm4's opacity and shadow settings at their stock values while it runs
#   - restores your theme and settings when it exits
#
# Needs:
#   - xfconf-query (Xfce)
#   - xterm, xdotool, scrot
#   - xprop, xwininfo (x11-utils)
#   - ImageMagick: convert, montage
#   - a screen at least 1200x600
#
# Writes:
#   - screenshots/<theme>.png: focused and unfocused window on a plain backdrop
#   - screenshots/hero.png: beacon-steel (else the first dark theme), full size
#   - screenshots/hero-light.png: beacon-steel-light (else the first light theme), full size
#   - screenshots/themes-dark.png: every dark theme, half size, named
#   - screenshots/themes-light.png: every light theme, half size, named
#   - screenshots/corner.png: the focused window's bottom-left corner, 8x, pixel for pixel
set -euo pipefail

die() {
	echo "capture.sh: $*" >&2
	exit 1
}

missing=()
for c in xfconf-query xterm xdotool xprop xwininfo scrot convert montage awk; do
	command -v "$c" >/dev/null || missing+=("$c")
done
[ ${#missing[@]} -eq 0 ] || {
	echo "capture.sh: missing tools: ${missing[*]} (Debian/Ubuntu: xfconf xterm xdotool x11-utils scrot imagemagick)" >&2
	exit 1
}

ROOT=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
OUT=$ROOT/screenshots
WORK=$ROOT/build.capture
X0=100 Y0=100 W=1100 H=460 # backdrop: the captured area
PIDS=()

# xfwm4 look settings, held at their stock values while capturing:
# - the values come from /usr/share/xfwm4/defaults
# - so the shots show a default desktop
# - yours come back on exit
declare -A STOCK=([frame_opacity]=100 [inactive_opacity]=100 [shadow_opacity]=50
	[shadow_delta_x]=0 [shadow_delta_y]=-3 [shadow_delta_width]=0 [shadow_delta_height]=0)

# Remember each setting before changing it.
# A setting never set in this profile goes in UNSET instead:
# - xfconf-query can neither read it nor plainly set it
# - it is created for the run and reset afterwards
declare -A WAS=() UNSET=()
WAS[theme]=$(xfconf-query -c xfwm4 -p /general/theme)
for k in "${!STOCK[@]}"; do
	if v=$(xfconf-query -c xfwm4 -p "/general/$k"); then WAS[$k]=$v; else UNSET[$k]=1; fi
done

# cleanup: run every restore even if one fails, then report the failures
cleanup() {
	local k failed=()
	for k in "${!WAS[@]}"; do
		xfconf-query -c xfwm4 -p "/general/$k" -s "${WAS[$k]}" || failed+=("$k")
	done
	for k in "${!UNSET[@]}"; do
		xfconf-query -c xfwm4 -p "/general/$k" -r || failed+=("$k")
	done
	if [ ${#PIDS[@]} -gt 0 ]; then kill "${PIDS[@]}" || failed+=("closing the xterms"); fi
	[ ${#failed[@]} -eq 0 ] || echo "capture.sh: could not restore: ${failed[*]}; reset them in Settings > Window Manager Tweaks" >&2
}
trap cleanup EXIT
for k in "${!STOCK[@]}"; do
	if [ -v "UNSET[$k]" ]; then
		xfconf-query -c xfwm4 -p "/general/$k" -n -t int -s "${STOCK[$k]}"
	else
		xfconf-query -c xfwm4 -p "/general/$k" -s "${STOCK[$k]}"
	fi
done

"$ROOT/install.sh"
rm -rf "$WORK"
mkdir -p "$WORK" "$OUT"

# term <title> <bg> <fg> <text>: start an xterm.
# - its PID goes in PIDS, for cleanup
# - its window id lands in WID
# - never call it through $(...): the subshell would lose the PID
term() {
	# stty -echo: keys pressed while capturing never show up in the shots
	xterm -T "$1" -bg "$2" -fg "$3" -e sh -c "stty -echo; printf '\033[?25l$4'; sleep 120" &
	PIDS+=($!)
	# find the window by PID, not title: a same-titled window from the last pass may still be closing
	WID=$(xdotool search --sync --onlyvisible --pid "$!" | tail -n1)
}

# geom <id>: the client area's absolute x, y, width, height
geom() { xwininfo -id "$1" | awk '/Absolute upper-left X/ {x = $NF} /Absolute upper-left Y/ {y = $NF} /Width:/ {w = $NF} /Height:/ {h = $NF} END {print x, y, w, h}'; }

# corner <theme>: crop the focused frame's bottom-left corner out of that theme's shot.
# Both windows are measured now, at capture time.
corner() {
	local bx by cx cy ch ext left bottom
	read -r bx by _ _ < <(geom "$backdrop")
	read -r cx cy _ ch < <(geom "$focused")
	ext=$(xprop -id "$focused" _NET_FRAME_EXTENTS)
	ext=${ext#*= }
	IFS=', ' read -r left _ _ bottom <<<"$ext"
	convert "$OUT/$1.png" -crop "56x56+$((cx - left - bx - 8))+$((cy + ch + bottom - by - 48))" +repage \
		-filter point -resize 800% "$OUT/corner.png"
}

# pass <tone> <backdrop> <window bg> <window fg> <theme>...:
# - opens the three windows in these colours
# - shoots each theme
# - closes the windows
# - adds each shot to SHOTS
pass() {
	local tone=$1 bg=$2 wbg=$3 wfg=$4 t bx by bw bh
	shift 4
	local text='\n  $ ls ~/projects\n  docs  beacon  notes\n\n  $ echo focus is easy to find\n  focus is easy to find\n'
	PIDS=()
	# the backdrop is decorated too; only its client area is captured
	term "beacon-backdrop-$tone" "$bg" "$bg" ''
	backdrop=$WID
	xdotool windowsize --sync "$backdrop" "$W" "$H" windowmove --sync "$backdrop" "$X0" "$Y0"
	read -r bx by _ _ < <(geom "$backdrop")
	term "Unfocused window" "$wbg" "$wfg" "$text"
	unfocused=$WID
	term "Focused window" "$wbg" "$wfg" "$text"
	focused=$WID
	xdotool windowsize "$unfocused" 460 300 windowmove "$unfocused" $((bx + 580)) $((by + 100))
	xdotool windowsize "$focused" 460 300 windowmove "$focused" $((bx + 60)) $((by + 60))
	xdotool mousemove 0 0
	# xfwm4 reloads a theme only when its name changes.
	# Start from the stock theme, so every shot below is a real switch,
	# even of the theme that was in use.
	xfconf-query -c xfwm4 -p /general/theme -s Default
	sleep 1
	for t in "$@"; do
		xfconf-query -c xfwm4 -p /general/theme -s "$t"
		sleep 1
		xdotool windowactivate --sync "$unfocused"
		xdotool windowactivate --sync "$focused"
		sleep 0.5
		# Measure the backdrop now: a theme switch can nudge and resize it.
		# Shoot a screen region: scrot -w would skip the windows on top.
		read -r bx by bw bh < <(geom "$backdrop")
		scrot -o -a "$bx,$by,$bw,$bh" "$OUT/$t.png"
		convert "$OUT/$t.png" -resize 50% "$WORK/$t.png"
		SHOTS+=(-label "$t" "$WORK/$t.png")
		if [ "$t" = "$hero_dark" ]; then corner "$t"; fi
	done
	kill "${PIDS[@]}"
	PIDS=()
}

# sort the built themes by the tone build.sh records in each themerc
darks=() lights=()
for d in "$ROOT"/build/*/xfwm4/; do
	t=$(basename "${d%/xfwm4/}")
	if grep -qxF '# tone: light' "$d/themerc"; then lights+=("$t"); else darks+=("$t"); fi
done
[ $((${#darks[@]} + ${#lights[@]})) -gt 0 ] || die "build/ holds no themes; run ./build.sh beacon.conf first"

# pick <want> <theme>...: <want> if it is among the themes, else the first theme
pick() {
	local want=$1 t
	shift
	for t in "$@"; do [ "$t" = "$want" ] && echo "$t" && return; done
	[ $# -gt 0 ] && echo "$1"
	return 0
}
hero_dark=$(pick beacon-steel "${darks[@]}")
hero_light=$(pick beacon-steel-light "${lights[@]}")

if [ ${#darks[@]} -gt 0 ]; then
	SHOTS=()
	pass dark '#3a4148' '#111f28' '#dcded6' "${darks[@]}"
	montage "${SHOTS[@]}" -tile 2x -geometry +8+8 -pointsize 16 -background '#2b3d4a' -fill '#f0f0e8' "$OUT/themes-dark.png"
	cp "$OUT/$hero_dark.png" "$OUT/hero.png"
fi
if [ ${#lights[@]} -gt 0 ]; then
	SHOTS=()
	pass light '#c4cac6' '#f7f7f2' '#1f2e38' "${lights[@]}"
	montage "${SHOTS[@]}" -tile 2x -geometry +8+8 -pointsize 16 -background '#e4e6df' -fill '#1f2e38' "$OUT/themes-light.png"
	cp "$OUT/$hero_light.png" "$OUT/hero-light.png"
fi
rm -rf "$WORK"
ls "$OUT"
