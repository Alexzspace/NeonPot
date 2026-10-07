# Neon Pot

Godot 4.6.2 Mobile / GDScript. Read README.md, docs/ARCHITECTURE.md,
docs/BUILDING.md, docs/PLAYING.md and docs/STATUS.md before changing behavior.

- Preserve existing work and create a recoverable checkpoint before gameplay or protocol changes.
- Update DEVDOC.md with meaningful iterations, actual validation and remaining gates.
- The host owns the deal and settlement. Never send the deck, seed or an opponent's hidden cards in recipient snapshots.
- Validate sender, seat, hand ID and revision before mutation. Test fixtures belong only in tests/.
- Two to six seats, equal starting stacks and persistent results across hands. No action timer, live odds, hand-strength helper or real-money integration.
- Run tools/selftest.ps1 with a Godot console executable; inspect summaries, errors and exit code.
- UI/lifecycle changes need a real graphical and touch-path check. Export success is not device validation.
- The root MIT license does not cover supplied music, fonts or the startup movie. Preserve THIRD_PARTY_NOTICES.md and licenses/.
- Never commit signing keys, credentials, private source media, personal preferences, caches or generated packages.
