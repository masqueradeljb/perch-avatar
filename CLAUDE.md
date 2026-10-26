# CLAUDE.md

@AGENTS.md

## Maintainer notes

- Release checklist (not done yet for 0.1.0): `scripts/build-app.sh --sign --notarize` (Developer ID "Varie.AI LLC", keychain notary profile `notary`) → GitHub Release with zip + dmg → `cd cli && npm publish` → Homebrew cask in `masqueradeljb/homebrew-tap` → `docs/demo.gif`.
- Art packs are produced by a private pipeline outside this repo (`varie_character/agent-avatar/pipeline`). Only redistributable packs go in `packs/`; personal/fan packs live in `~/.perch/packs/<id>` and are selected with `~/.perch/config.json` `{"pack": "<id>"}`.
