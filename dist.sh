#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# SPDX-FileCopyrightText: 2026 Wampeter Foma
#
# dist.sh: build the themes and pack them into a release archive.
#
# Usage:
#   ./dist.sh [config]
#
# Arguments:
#   - config: the config to build (default beacon.conf)
#
# What it does:
#   - runs ./build.sh with the config
#   - packs the built themes, install.sh, README and both licences
#   - all under one top-level folder, xfce4-beacon-theme/
#
# Needs:
#   - the build tools (build.sh checks them)
#   - tar, gzip
#
# Writes:
#   - dist/xfce4-beacon-theme.tar.gz
set -euo pipefail

NAME=xfce4-beacon-theme

die() {
	echo "dist.sh: $*" >&2
	exit 1
}

missing=()
for c in tar gzip realpath; do command -v "$c" >/dev/null || missing+=("$c"); done
[ ${#missing[@]} -eq 0 ] || die "missing tools: ${missing[*]}"

# resolve the config against the caller's directory, before the cd
CONF=$(realpath -m -- "${1:-$(dirname "$0")/beacon.conf}")
cd "$(dirname "$0")"

./build.sh "$CONF"

rm -rf dist
mkdir -p "dist/$NAME"
cp -r build install.sh README.md LICENSE LICENSE-ART "dist/$NAME/"
# root ownership in the archive: never the packer's user name
tar --owner=0 --group=0 --numeric-owner -czf "dist/$NAME.tar.gz" -C dist "$NAME"
rm -r "dist/$NAME"
echo "packed dist/$NAME.tar.gz"
