# Changelog

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versions: [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

How to release:
1. Rename `Unreleased` below to the new version and date, e.g. `## [1.0.0] - 2026-11-20`.
2. Add a new, empty `Unreleased` section above it.
3. Commit, then tag the commit `v<version>` (e.g. `v1.0.0`) and push the tag.
4. CI builds the archive and creates the release, with that version's section as
   its notes.

## [Unreleased]

### Added

- Twelve xfwm4 themes: steel, teal and sand accents, in dark and light tones,
  with neutral or accent glyphs.
- Focus cue: an accent stripe and corner brackets on the focused window.
- Unfocused tint: a hint of the accent on unfocused windows (`inactive=tint`), or
  none (`inactive=neutral`).
- Visible resize corners: 32px brackets on the bottom corners.
- Button shapes `disc`, `ring` and `bare`, and glyph sets a, b and c.
- `beacon.conf`: every theme generated from one config file.
- `build.sh`, `install.sh`, and a container build (`Dockerfile`).
- `capture.sh` and `previews.sh` to regenerate the screenshots.
- `dist.sh` and CI to build release archives.
