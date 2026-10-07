# Architecture

Godot 4.6.2 Mobile renderer, GDScript, landscape UI. `scenes/boot.tscn` plays the intro while loading `scenes/main.tscn`.

| Area | Main files | Responsibility |
| --- | --- | --- |
| Application | `scripts/main.gd` | Home/table flows, modals, preferences, animation sequencing |
| Poker rules | `scripts/poker_engine.gd` | Legal actions, betting rounds, side pots and awards |
| Session | `scripts/table_session.gd` | Host authority, recipient snapshots, AI and network actions |
| Discovery | `scripts/lan_discovery.gd` | Local UDP room discovery and expiry |
| Chips | `scripts/chip_inventory.gd`, `chip_display.gd`, `manual_chip_panel.gd` | Exact denomination inventories and their presentation |
| Cards | `scripts/card_view.gd`, `public_card.gd`, `card_themes.gd` | Private peeks, public gestures and styling |
| Personal tools | `scripts/deck_workshop.gd`, `music_player.gd` | Local drawing recipes and local audio library |
| Feedback | `scripts/feedback.gd`, `haptic_driver.gd` | Generated sounds and device-capability-aware haptics |

## Contracts

- Only the host shuffles and adjudicates. Snapshots sent to a recipient must not include the deck, random seed or another player's hidden cards.
- Actions validate sender, seat, hand ID and server revision before mutation. Cosmetic events cannot change economic state.
- `raise_to` is the total round contribution, not an additional amount.
- Denominations are 1, 5, 10, 50, 100 and 500. Chip transfers preserve composition except for necessary change-making. Unconfirmed selections are private.
- Betting, cosmetic and chip revisions prevent stale commands and repeated visual transfers.
- Production deals are random. Deterministic fixture deals belong only in `tests/`.
- Initial stacks are equal. Winnings persist across hands. No action timers or live decision aids are present.
- Home titles configure wrapping before assigning text so long English lines cannot enlarge and poison the cached layout rectangle; title-specific leading fits two lines in the existing panel.
- A fresh preference store uses English. Saved `en`/`zh` is respected; missing or invalid language values use English.
- The existing custom user-data directory is retained for compatibility; no preferences or imported files are included in the repository or exports.

See the tests for executable edge cases. UI/lifecycle changes require graphical checks in addition to headless assertions. Export success does not substitute for device validation.
