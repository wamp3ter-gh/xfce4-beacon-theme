#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Wampeter Foma
# Render the xfwm4 themes a config file describes into build/<theme>/xfwm4.
# Usage: ./build.sh <config>   (the shipped config is beacon.conf)
# The config format is documented at the top of beacon.conf.
set -euo pipefail

die() {
	echo "build.sh: $*" >&2
	exit 1
}

# every tool this script runs, checked up front so a missing one can't stop a half-done build
missing=()
for c in rsvg-convert bc realpath; do command -v "$c" >/dev/null || missing+=("$c"); done
[ ${#missing[@]} -eq 0 ] || die "missing tools: ${missing[*]} (install them, see README Requirements, or build with docker: see README)"

[ $# -eq 1 ] || die "usage: ./build.sh <config>, for example ./build.sh beacon.conf"
# resolve the config against the caller's directory, before the cd
CONF=$(realpath -m -- "$1")
cd "$(dirname "$0")"

# --- fixed sizes (px, 4px ramp) -----------------------------------------------
TITLE=32     # title bar height
STRIPE=3     # focus stripe along the top of the title bar
CORNER=32    # lit corner bracket, each way along the window edge
EDGE=1       # outer hairline on rails thicker than 2px
CLOSE_GAP=12 # extra space before close
BTN=24       # button size, every shape
declare -A GLYPH_SIZE=([bare]=16 [disc]=13 [ring]=13)
BUTTONS=(menu stick shade hide max close)
# inactive=tint strengths, percent of the accent (see set_roles)
TINT_DARK=30  # dark tone: unfocused stripe and corners
WASH_LIGHT=10 # light tone: unfocused title bar

# --- primitives ---------------------------------------------------------------
SLATE_900='#111f28'
SLATE_850='#16232c'
SLATE_800='#1f2e38'
SLATE_750='#213544'
SLATE_700='#2b3d4a'
SLATE_600='#3a4d5b'
SLATE_500='#5f788a'
GREY_400='#8a9a9f'
CREAM_100='#f0f0e8'
CREAM_200='#dcded6'
BRICK='#e0664a'
BRICK_DARK='#b84a33'
# light tone
PALE_100='#eeefe9'
PALE_200='#e4e6df'
PALE_300='#e0e2dc'
PALE_400='#d7dad3'
PALE_500='#cdd2cc'
PALE_600='#c9ccc4'
PALE_700='#b9c0bd'
INK_900='#1f2e38'
INK_500='#6b7b80'

# --- roles, per focus state and tone: set_roles active|inactive ------------
# R_HOVER and R_HOVER_GLYPH: a hovered (non-close) disc or ring and its glyph.
# R_ON_GLYPH: a glyph on an accent-filled button (pressed or toggled).
set_roles() {
	if [ "$TONE" = dark ]; then
		R_HOVER=$CREAM_100 R_HOVER_GLYPH=$SLATE_900 R_ON_GLYPH=$SLATE_900
		if [ "$1" = active ]; then
			R_TITLE=$SLATE_750
			R_STRIPE=$ACCENT
			R_RAIL=$SLATE_600
			R_EDGE=$SLATE_500
			R_TL=$C_TL R_TR=$C_TR R_BL=$C_BL R_BR=$C_BR
			R_MESH=$ACCENT
			R_GLYPH=$CREAM_200
			R_SHAPE=$SLATE_500
			R_SHAPE_FILL=$SLATE_600
		else
			R_TITLE=$SLATE_850
			R_RAIL=$SLATE_800
			R_EDGE=$SLATE_700
			R_STRIPE=$R_EDGE
			R_TL=$SLATE_600 R_TR=$SLATE_600 R_BL=$SLATE_600 R_BR=$SLATE_600
			R_MESH=$SLATE_700
			R_GLYPH=$GREY_400
			R_SHAPE=$SLATE_700
			R_SHAPE_FILL=$SLATE_800
		fi
	else
		# cream hover would vanish on a pale title bar, so hover goes dark slate
		R_HOVER=$SLATE_600 R_HOVER_GLYPH=$CREAM_100 R_ON_GLYPH=$CREAM_100
		if [ "$1" = active ]; then
			R_TITLE=$PALE_200
			R_STRIPE=$ACCENT
			R_RAIL=$PALE_700
			R_EDGE=$GREY_400
			R_TL=$C_TL R_TR=$C_TR R_BL=$C_BL R_BR=$C_BR
			R_MESH=$ACCENT
			R_GLYPH=$SLATE_700
			R_SHAPE=$PALE_700
			R_SHAPE_FILL=$PALE_500
		else
			R_TITLE=$PALE_100
			R_RAIL=$PALE_400
			R_EDGE=$PALE_600
			R_STRIPE=$R_EDGE
			R_TL=$PALE_700 R_TR=$PALE_700 R_BL=$PALE_700 R_BR=$PALE_700
			R_MESH=$PALE_600
			R_GLYPH=$GREY_400
			R_SHAPE=$PALE_400
			R_SHAPE_FILL=$PALE_300
		fi
	fi
	# inactive=tint: unfocused windows keep a hint of the accent, placed where it
	# costs the focus cue least.
	# - dark: TINT_DARK percent in the stripe and corners. The side lines stay
	#   neutral, as they are on the focused window.
	# - light: a WASH_LIGHT percent wash over the title bar. Light accents sit near
	#   3:1 against the neutral stripe already, so any tint there drops below it;
	#   the wash leaves the stripe and corners, and so the focus cue, untouched.
	if [ "$1" = inactive ] && [ "$INACTIVE" = tint ]; then
		if [ "$TONE" = dark ]; then
			R_STRIPE=$(mix "$ACCENT" "$R_STRIPE" "$TINT_DARK")
			R_TL=$(mix "$ACCENT" "$R_TL" "$TINT_DARK")
			R_TR=$R_TL R_BL=$R_TL R_BR=$R_TL
		else
			R_TITLE=$(mix "$ACCENT" "$R_TITLE" "$WASH_LIGHT")
		fi
	fi
}

# mix <#rrggbb a> <#rrggbb b> <percent of a>: the two colours blended, in sRGB
mix() {
	local a=${1#\#} b=${2#\#} t=$3 i out=""
	for i in 0 2 4; do
		out+=$(printf '%02x' $(((16#${a:i:2} * t + 16#${b:i:2} * (100 - t) + 50) / 100)))
	done
	echo "#$out"
}

# render <name> <w> <h> <svg body>
render() {
	printf '<svg xmlns="http://www.w3.org/2000/svg" width="%s" height="%s" shape-rendering="crispEdges">%s</svg>' \
		"$2" "$3" "$4" | rsvg-convert -o "$OUT/$1.png"
}

# --- frame pieces ---------------------------------------------------------------
# GRAB = handle size, LINE = drawn line, KNEE = bracket thickness. Drawing hugs
# the window (inner side); the rest of the handle is transparent.
frame() {
	local s=$1 t
	t="<rect width='8' height='$TITLE' fill='$R_TITLE'/><rect width='8' height='$STRIPE' fill='$R_STRIPE'/>"
	for i in 1 2 3 4 5; do render "title-$i-$s" 8 "$TITLE" "$t"; done
	# c = corner piece: the handle plus the bracket's reach, so the bracket stays
	# CORNER long whatever the handle size
	local b=$GRAB l=$LINE k=$KNEE c=$((GRAB + CORNER)) e=0 fill=$R_RAIL
	[ "$l" -gt 2 ] && e=$EDGE
	[ "$l" -le 2 ] && fill=$R_EDGE
	# mesh: the handle area outside the drawn line as a 1px checkerboard. xfwm4
	# cuts every pixel that is not fully opaque out of the frame (no drawing, no
	# clicks), so a see-through handle can only be made of solid pixels with gaps.
	local m=""
	if [ "$MESH" = 1 ]; then
		m="<defs><pattern id='m' width='2' height='2' patternUnits='userSpaceOnUse'><rect width='1' height='1' fill='$R_MESH'/><rect x='1' y='1' width='1' height='1' fill='$R_MESH'/></pattern></defs>"
	fi
	mesh() { [ -n "$m" ] && echo "<rect x='$1' y='$2' width='$3' height='$4' fill='url(#m)'/>"; return 0; }
	# sides are 2px long so the checkerboard tiles
	render "top-left-$s" "$b" "$TITLE" "$m$(mesh 0 0 $((b - k)) "$TITLE")<rect x='$((b - k))' width='$k' height='$TITLE' fill='$R_TL'/>"
	render "top-right-$s" "$b" "$TITLE" "$m$(mesh "$k" 0 $((b - k)) "$TITLE")<rect width='$k' height='$TITLE' fill='$R_TR'/>"
	render "left-$s" "$b" 2 "$m$(mesh 0 0 $((b - l)) 2)<rect x='$((b - l))' width='$l' height='2' fill='$fill'/><rect x='$((b - l))' width='$e' height='2' fill='$R_EDGE'/>"
	render "right-$s" "$b" 2 "$m$(mesh "$l" 0 $((b - l)) 2)<rect width='$l' height='2' fill='$fill'/><rect x='$((l - e))' width='$e' height='2' fill='$R_EDGE'/>"
	render "bottom-$s" 2 "$b" "$m$(mesh 0 "$l" 2 $((b - l)))<rect width='2' height='$l' fill='$fill'/><rect y='$((l - e))' width='2' height='$e' fill='$R_EDGE'/>"
	# bottom corners: an L, CORNER long each way; the inner part sits under the client
	local arm=$((c - b + k))
	render "bottom-left-$s" "$c" "$c" "$m$(mesh 0 0 "$b" "$c")$(mesh "$b" $((c - b)) $((c - b)) "$b")<g fill='$R_BL'><rect x='$((b - k))' width='$k' height='$arm'/><rect x='$((b - k))' y='$((c - b))' width='$arm' height='$k'/></g>"
	render "bottom-right-$s" "$c" "$c" "$m$(mesh $((c - b)) 0 "$b" "$c")$(mesh 0 $((c - b)) $((c - b)) "$b")<g fill='$R_BR'><rect x='$((c - b))' width='$k' height='$arm'/><rect y='$((c - b))' width='$arm' height='$k'/></g>"
}

# --- glyphs -------------------------------------------------------------------
# glyph <name> <colour> <stroke>: markup on a 24 grid; <stroke> is in grid units
# so it renders near 2px at any glyph size. Names ending -t are the toggled state.
# Which set (a, b, c) draws each button comes from GMAP.
glyph() {
	local c=$2 w=$3 set=${GMAP[${1%-t}]}
	local st="fill='none' stroke='$c' stroke-width='$w'"
	case $set-$1 in
	a-menu) echo "<g fill='$c'><rect x='9' width='6' height='6'/><rect x='9' y='9' width='6' height='6'/><rect x='9' y='18' width='6' height='6'/></g>" ;;
	b-menu) echo "<path $st d='M3 5H21M3 12H21M3 19H21'/>" ;;
	c-menu) echo "<path $st d='M4 8L12 16L20 8'/>" ;;

	a-stick) echo "<path $st stroke-linejoin='round' d='M6 1.5H18M8.25 1.5V9L4.5 14.25H19.5L15.75 9V1.5M12 14.25V22.5'/>" ;;
	a-stick-t) echo "<path fill='$c' stroke='$c' stroke-width='$w' stroke-linejoin='round' d='M6 1.5H18M8.25 1.5V9L4.5 14.25H19.5L15.75 9V1.5Z'/><path $st d='M12 14.25V22.5'/>" ;;
	b-stick) echo "<rect x='3' y='9' width='12' height='12' $st/><rect x='9' y='3' width='12' height='12' fill='$c'/>" ;;
	b-stick-t) echo "<rect x='3' y='9' width='12' height='12' fill='$c'/><rect x='9' y='3' width='12' height='12' fill='$c'/>" ;;
	c-stick | c-stick-t) echo "<path $st d='M12 3V15M6 9L12 3L18 9M3 21H21'/>" ;;

	a-shade) echo "<rect x='1.5' width='21' height='4.5' fill='$c'/><path $st d='M6 19.5L12 13.5L18 19.5'/>" ;;
	a-shade-t) echo "<rect x='1.5' width='21' height='4.5' fill='$c'/><path $st d='M6 13.5L12 19.5L18 13.5'/>" ;;
	b-shade | b-shade-t) echo "<rect x='2' y='3' width='20' height='7' fill='$c'/><path $st stroke-dasharray='3 3' d='M2 15H22M2 21H22'/>" ;;
	c-shade) echo "<path $st d='M5 12L12 5L19 12M5 20L12 13L19 20'/>" ;;
	c-shade-t) echo "<path $st d='M5 4L12 11L19 4M5 12L12 19L19 12'/>" ;;

	a-hide) echo "<rect x='1.5' y='19.5' width='21' height='4.5' fill='$c'/><path $st d='M6 4.5L12 10.5L18 4.5'/>" ;;
	b-hide) echo "<rect x='3' y='17' width='18' height='4' fill='$c'/>" ;;
	c-hide) echo "<path $st d='M12 2V14M6 8L12 14L18 8'/><rect x='3' y='18' width='18' height='4' fill='$c'/>" ;;

	a-max) echo "<path $st d='M1.5 9V1.5H9M15 1.5H22.5V9M22.5 15V22.5H15M9 22.5H1.5V15'/>" ;;
	a-max-t) echo "<path $st d='M1.5 9H9V1.5M15 1.5V9H22.5M22.5 15H15V22.5M9 22.5V15H1.5'/>" ;;
	b-max) echo "<rect x='3' y='3' width='18' height='18' $st/>" ;;
	b-max-t) echo "<rect x='3' y='8' width='13' height='13' $st/><path $st d='M8 8V3H21V16H16'/>" ;;
	c-max) echo "<path $st d='M14 3H21V10M21 3L13 11M10 21H3V14M3 21L11 13'/>" ;;
	c-max-t) echo "<path $st d='M20 4L14 10M14 4V10H20M4 20L10 14M10 20V14H4'/>" ;;

	a-close) echo "<path fill='none' stroke='$c' stroke-width='$(echo "$w * 1.25" | bc)' d='M3 3L21 21M21 3L3 21'/>" ;;
	b-close) echo "<path fill='none' stroke='$c' stroke-width='$(echo "$w * 1.4" | bc)' d='M5 5L19 19M19 5L5 19'/>" ;;
	c-close) echo "<path fill='none' stroke='$c' stroke-width='$(echo "$w * 1.4" | bc)' stroke-linecap='round' d='M5 5L19 19M19 5L5 19'/>" ;;
	*) die "no glyph $set-$1" ;;
	esac
}

# --- button container: shape <state> <is-close> -> SH (markup, 24 grid), may change GC
shape() {
	local st=$1 close=$2 ring=$R_SHAPE fill=$R_SHAPE_FILL
	SH=""
	case $st in
	prelight)
		if [ "$close" = 1 ]; then ring=$BRICK; else ring=$R_HOVER; fi
		fill=$ring
		;;
	pressed)
		if [ "$close" = 1 ]; then fill=$BRICK_DARK; else fill=$ACCENT; fi
		GC=$R_ON_GLYPH
		;;
	esac
	case $SHAPE-$st in
	bare-prelight)
		if [ "$close" = 1 ]; then
			SH="<rect width='24' height='24' rx='4' fill='$BRICK'/>"
			GC=$R_HOVER_GLYPH
		else
			SH="<rect width='24' height='24' rx='4' fill='$SLATE_600'/>"
			GC=$CREAM_100
		fi
		;;
	bare-pressed) SH="<rect width='24' height='24' rx='4' fill='$fill'/>" ;;
	bare-*) ;;
	disc-*)
		SH="<circle cx='12' cy='12' r='11' fill='$fill'/>"
		[ "$st" = prelight ] && GC=$R_HOVER_GLYPH
		;;
	ring-pressed) SH="<circle cx='12' cy='12' r='11' fill='$fill'/>" ;;
	ring-*)
		SH="<circle cx='12' cy='12' r='10.75' fill='none' stroke='$ring' stroke-width='1.5'/>"
		[ "$st" = prelight ] && GC=$ring
		;;
	esac
	return 0
}

# button <file> <glyph> <state> [lead]
button() {
	local file=$1 g=$2 st=$3 lead=${4:-0} close=0 tog=0
	[ "$file" = close ] && close=1
	[[ $g == *-t ]] && tog=1
	set_roles "$([ "$st" = inactive ] && echo inactive || echo active)"
	GC=$R_GLYPH
	[ "$st" = active ] && [ "$INK" = accent ] && GC=$ACCENT
	[ "$tog" = 1 ] && [ "$st" != inactive ] && GC=$ACCENT
	shape "$st" "$close"
	# a toggled button lights up in the accent: glyph colour alone is too faint a cue
	# (under 1.5:1 against the normal glyph), and glyph set c draws stick the same both ways
	if [ "$tog" = 1 ] && [ "$st" = active ]; then
		if [ "$SHAPE" = bare ]; then
			SH="<rect width='24' height='24' rx='4' fill='$ACCENT'/>"
		else
			SH="<circle cx='12' cy='12' r='11' fill='$ACCENT'/>"
		fi
		GC=$R_ON_GLYPH
	fi
	local gs=${GLYPH_SIZE[$SHAPE]}
	local w=$((BTN + lead)) py=$((STRIPE + (TITLE - STRIPE - BTN + 1) / 2))
	local gscale sw gx gy
	gscale=$(echo "scale=4; $gs / 24" | bc)
	sw=$(echo "scale=3; 2 * 24 / $gs" | bc)
	gx=$(echo "$lead + ($BTN - $gs) / 2" | bc -l)
	gy=$(echo "$py + ($BTN - $gs) / 2" | bc -l)
	local body="<rect width='$w' height='$TITLE' fill='$R_TITLE'/><rect width='$w' height='$STRIPE' fill='$R_STRIPE'/>"
	body+="<g transform='translate($lead $py)' shape-rendering='geometricPrecision'>$SH</g>"
	body+="<g transform='translate($gx $gy) scale($gscale)' shape-rendering='geometricPrecision'>$(glyph "$g" "$GC" "$sw")</g>"
	render "$file-$st" "$w" "$TITLE" "$body"
}

buttons() {
	local st
	for st in active inactive prelight pressed; do
		button menu menu "$st"
		button stick stick "$st"
		button stick-toggled stick-t "$st"
		button shade shade "$st"
		button shade-toggled shade-t "$st"
		button hide hide "$st"
		button maximize max "$st"
		button maximize-toggled max-t "$st"
		button close close "$st" "$CLOSE_GAP"
	done
}

themerc() {
	cat >"$OUT/themerc" <<EOF
# $NAME xfwm4 theme; generated by xfce4-beacon-theme build.sh from ${CONF##*/}
# SPDX-License-Identifier: CC-BY-NC-SA-4.0
# SPDX-FileCopyrightText: 2026 Wampeter Foma
# tone: $TONE
active_text_color=$TEXT_ACTIVE
inactive_text_color=$TEXT_INACTIVE
title_vertical_offset_active=$((STRIPE / 2 + 1))
title_vertical_offset_inactive=$((STRIPE / 2 + 1))
button_offset=4
button_spacing=4
maximized_offset=0
full_width_title=true
title_shadow_active=false
title_shadow_inactive=false
show_app_icon=false
EOF
}

# --- config -------------------------------------------------------------------
# word <s>: s is a plain name (letters, digits, _ and -). Every name from the
# config is checked with this before it is used as an array key: bash expands a
# key again inside [[ -v ]], so a key like $(cmd) would run cmd.
word() { [[ $1 =~ ^[A-Za-z0-9_-]+$ ]]; }
# has <array> <key>: key is a plain name and present in the named array
has() {
	local -n _arr=$1
	word "$2" && [[ -v _arr[$2] ]]
}

[ -f "$CONF" ] || die "no config: $CONF"
# glyph set c is built in (every button drawn from set c), so a config needs no
# glyphs line to use the default
declare -A COLOURS=() GLYPHSETS=([c]='') SEEN=()
THEMES=()
n=0
while IFS= read -r raw || [ -n "$raw" ]; do
	n=$((n + 1))
	# a config saved with Windows line endings ends each line in \r
	read -r kind name rest <<<"${raw%$'\r'}"
	case $kind in
	'' | '#'*) continue ;;
	colour)
		word "$name" || die "$CONF:$n: colour name '$name': use letters, digits, _ and -"
		[[ $rest =~ ^#[0-9a-fA-F]{6}$ ]] || die "$CONF:$n: colour $name: want #rrggbb, got '$rest'"
		COLOURS[$name]=$rest
		;;
	glyphs)
		word "$name" || die "$CONF:$n: glyphs name '$name': use letters, digits, _ and -"
		GLYPHSETS[$name]=$rest
		;;
	theme)
		# a template: plain characters plus {placeholders}; checked again once filled in
		[[ $name =~ ^[A-Za-z0-9_{}.-]+$ ]] || die "$CONF:$n: theme name '$name': use letters, digits, _ . - and {placeholders}"
		THEMES+=("$n $name $rest")
		;;
	*) die "$CONF:$n: unknown entry '$kind'" ;;
	esac
done <"$CONF"
[ ${#THEMES[@]} -gt 0 ] || die "$CONF: no theme lines"

# load_glyphs <set name> <line>: fill GMAP, every button defaulting to c
load_glyphs() {
	has GLYPHSETS "$1" || die "$CONF:$2: unknown glyphs '$1'"
	GMAP=()
	local b kv
	local -a kvs
	for b in "${BUTTONS[@]}"; do GMAP[$b]=c; done
	read -ra kvs <<<"${GLYPHSETS[$1]}"
	for kv in "${kvs[@]}"; do
		has GMAP "${kv%%=*}" || die "$CONF: glyphs $1: unknown button '${kv%%=*}'"
		[[ ${kv#*=} =~ ^[abc]$ ]] || die "$CONF: glyphs $1: set must be a, b or c in '$kv'"
		GMAP[${kv%%=*}]=${kv#*=}
	done
}

# corner <value> <line>: a focused-window corner colour; empty = the accent,
# else a colour name from the config or #rrggbb
corner() {
	if [ -z "$1" ]; then
		echo "$ACCENT"
	elif [[ $1 =~ ^#[0-9a-fA-F]{6}$ ]]; then
		echo "$1"
	elif has COLOURS "$1"; then
		echo "${COLOURS[$1]}"
	else
		die "$CONF:$2: corner colour '$1' is not a colour name or #rrggbb"
	fi
}

declare -A GMAP=() P=()
# render into build.new and swap it in only when every theme built, so a bad
# theme line never leaves a half-made build/
rm -rf build.new
for entry in "${THEMES[@]}"; do
	read -ra f <<<"$entry"
	line=${f[0]} tmpl=${f[1]}
	P=([colour]='' [tone]=dark [inactive]=tint [shape]=disc [glyphs]=c [ink]=cream [line]=1 [knee]=3 [grab]=4 [mesh]=0 [tl]='' [tr]='' [bl]='' [br]='')
	for kv in "${f[@]:2}"; do
		has P "${kv%%=*}" || die "$CONF:$line: unknown key '${kv%%=*}'"
		P[${kv%%=*}]=${kv#*=}
	done
	[ -n "${P[colour]}" ] || die "$CONF:$line: theme $tmpl needs colour="
	# whole numbers from 1, no leading zero (bash reads 08 as bad octal)
	for k in line knee grab; do [[ ${P[$k]} =~ ^[1-9][0-9]*$ ]] || die "$CONF:$line: $k must be a whole number of 1 or more, not '${P[$k]}'"; done
	for k in colour tone inactive shape glyphs ink; do
		[[ ${P[$k]} =~ ^[^,]+(,[^,]+)*$ ]] || die "$CONF:$line: $k is empty or has an empty item: '${P[$k]}'"
	done
	LINE=${P[line]} KNEE=${P[knee]} GRAB=${P[grab]} MESH=${P[mesh]}
	[[ $MESH =~ ^[01]$ ]] || die "$CONF:$line: mesh is 0 or 1"
	[ "$LINE" -le "$GRAB" ] && [ "$KNEE" -le "$GRAB" ] ||
		die "$CONF:$line: need line and knee <= grab"
	IFS=, read -ra cols <<<"${P[colour]}"
	IFS=, read -ra shapes <<<"${P[shape]}"
	IFS=, read -ra gsets <<<"${P[glyphs]}"
	IFS=, read -ra inks <<<"${P[ink]}"
	IFS=, read -ra tones <<<"${P[tone]}"
	IFS=, read -ra inacts <<<"${P[inactive]}"
	for TONE in "${tones[@]}"; do
	case $TONE in
	dark) TEXT_ACTIVE=$CREAM_100 TEXT_INACTIVE=$GREY_400 ;;
	light) TEXT_ACTIVE=$INK_900 TEXT_INACTIVE=$INK_500 ;;
	*) die "$CONF:$line: tone must be dark or light, not '$TONE'" ;;
	esac
	for col in "${cols[@]}"; do
		has COLOURS "$col" || die "$CONF:$line: unknown colour '$col'"
		ACCENT=${COLOURS[$col]}
		C_TL=$(corner "${P[tl]}" "$line")
		C_TR=$(corner "${P[tr]}" "$line")
		C_BL=$(corner "${P[bl]}" "$line")
		C_BR=$(corner "${P[br]}" "$line")
		for SHAPE in "${shapes[@]}"; do
			has GLYPH_SIZE "$SHAPE" || die "$CONF:$line: shape must be bare, disc or ring, not '$SHAPE'"
			for gs in "${gsets[@]}"; do
				load_glyphs "$gs" "$line"
				for INK in "${inks[@]}"; do
					[[ $INK =~ ^(cream|accent)$ ]] || die "$CONF:$line: ink must be cream or accent, not '$INK'"
					for INACTIVE in "${inacts[@]}"; do
						[[ $INACTIVE =~ ^(neutral|tint)$ ]] || die "$CONF:$line: inactive must be neutral or tint, not '$INACTIVE'"
						NAME=${tmpl//\{colour\}/$col}
						NAME=${NAME//\{shape\}/$SHAPE}
						NAME=${NAME//\{glyphs\}/$gs}
						NAME=${NAME//\{ink\}/$INK}
						NAME=${NAME//\{tone\}/$TONE}
						NAME=${NAME//\{inactive\}/$INACTIVE}
						# a folder name: no /, no leading dot (so no . or ..), no unfilled {..}
						[[ $NAME =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] ||
							die "$CONF:$line: theme name '$NAME' must start with a letter, digit or _ and hold only letters, digits, _ . and - (unknown {placeholder}?)"
						[[ -v SEEN[$NAME] ]] && die "$CONF:$line: theme name '$NAME' made twice; add {colour}/{tone}/{inactive}/{shape}/{glyphs}/{ink} to the name"
						SEEN[$NAME]=1
						OUT=build.new/$NAME/xfwm4
						mkdir -p "$OUT"
						set_roles active
						frame active
						set_roles inactive
						frame inactive
						buttons
						themerc
						echo "built build/$NAME/xfwm4"
					done
				done
			done
		done
	done
	done
done
# only replace the old build when this one produced something
[ -d build.new ] || die "$CONF: no themes built; previous build/ left in place"
rm -rf build
mv build.new build
