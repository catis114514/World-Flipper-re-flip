# Godot Offline Migration Roadmap

## Ordered Delivery

- [ ] Complete and activate child task `07-13-godot-core-battle-slice`.
- [ ] Add a progression/home child after the battle slice proves local save and static repository contracts.
- [ ] Add gacha, economy, shop, mail-equivalent rewards, and CN-original equipment as an offline systems child.
- [ ] Add broad quest/event/content conversion and original visual/audio/animation parity as separate children.
- [ ] Add Android input, performance, packaging, and save migration after the Windows/headless build is stable.
- [ ] Run a final CN parity review across child deliverables and document intentionally offline-only differences.

## Parent Validation Gates

- Every child must identify its CN source evidence and must not silently substitute JP/global values.
- No child may introduce an AIR, Node.js, HTTP, CDN, account SDK, payment, or ANE runtime dependency.
- Host reference artifacts must never be deleted or overwritten.
- Save schema and static-content formats require explicit versioning and migration tests.
- Battle compatibility changes require deterministic fixture/replay tests before integration.

## Rollback Shape

Each child lands behind stable interfaces and keeps generated artifacts reproducible from source inputs. If a later converter or presentation layer fails, retain the previous generated content version and verified simulation/save contracts.
