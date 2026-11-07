# liteweight vendoring note

liteweight vendors MuscleMap **1.6.4** from commit `7dc03071e03052e8bd4f6351e9176994cd28aa7d`,
the pinned MIT-licensed release from <https://github.com/melihcolpan/MuscleMap>.

The vendored source keeps the package's `MuscleMap` library product, body renderer,
highlight/heatmap APIs, localization resources, and MIT `LICENSE`. liteweight adds the small
public `MuscleHitTester` facade so an app-owned, hold-gated gesture can reuse the
renderer’s existing coordinate transforms and path hit testing without duplicating
anatomy data.

The upstream `Sources` tree (including DocC), `Tests`, package manifest, and license are
preserved byte-for-byte. The hit-test facade and this provenance note are additions.
The upstream example apps, screenshots, and CocoaPods packaging are not part of this Swift package.
