# Working plan: WhatCable

**Source review — 23 September 2026**
**Observed source:** Gitea `main`, `2959b2204fcade0c85a6aeedb8bf2830958ad2ec`, inspected from the clean HP-Lab clone. A separate Mac checkout at this HEAD has an untracked local `build-local-app.sh`; it was left untouched. This plan does not infer ownership, upstream maintainer status or current release state from the repository snapshot.

## Purpose

Maintain the macOS menu-bar app and CLI that interpret USB-C port, cable, charger, device and Thunderbolt state exposed by IOKit. The product aims to explain charging and data bottlenecks in accessible language, with optional advanced diagnostics and a Pro feature set.

## Current observed source state

The README describes a Swift-based app and CLI for macOS 14+ on Apple Silicon. It documents IOKit service reads, cable/PD decoding, connected-device topology, widgets, translations, local settings and signed/notarised distribution outside the Mac App Store. It also documents a manual, opt-in diagnostic contribution path and update checks that contact GitHub releases; do not reduce these into a broad promise that the app never communicates externally.

The README gives local Swift build/run/test, smoke-test and release-script entry points. `TRANSLATIONS.md` requires translation keys and format specifiers to remain aligned with English and asks contributors to preserve established technical terms; the release note at `release-notes/v0.5.13.md` records a specific cable-endpoint detection fix. These documents do not establish which version is currently published or installed.

## Architecture and operating boundary

- The app and CLI use macOS IOKit observations; they are not a hardware-control or cable-certification system.
- Present unusual e-marker values as signals for inspection, not as proof of counterfeit hardware. Distinguish reported capability, negotiated link and observed fault.
- Keep diagnostics local by default. Any contributed diagnostic material remains an explicit user action and must follow the documented anonymisation/consent path.
- Keep technical protocol labels searchable and stable across translations; translate explanatory prose without changing keys or format placeholders.
- Repository HEAD does not establish upstream ownership, maintainer authority or user impact. Confirm those separately before making release/maintainer claims.

## Decisions to preserve

1. Treat IOKit availability as a platform boundary; document unsupported hardware/OS combinations from tested evidence.
2. Distinguish USB-PD advertised capabilities, negotiated state and observed system telemetry in the UI and CLI.
3. Keep claims about USB-IF certification, cable identity and trust indicators carefully scoped to the available identifiers/database.
4. Preserve diagnostic opt-in and data-minimisation behavior; do not add background capture or upload by implication.
5. Preserve translation key parity and technical terminology; test every locale’s strings and format specifiers.
6. Treat signing, notarisation, Homebrew publication and release tags as delivery gates, not facts implied by source scripts or a release-note file.

## Next actions

1. Run the documented Swift test/build and smoke checks on supported Apple Silicon hardware, recording OS/Xcode versions and results.
2. Maintain a hardware/OS compatibility matrix for IOKit service coverage and probe-failure behavior.
3. Review diagnostics for clarity around measured versus inferred limits, especially certification lookup and unusual cable-field warnings.
4. Validate translation key/placeholder parity and complete maintainer review for languages with designated maintainers before release.
5. Verify the current signed/notarised artifact, release page and Homebrew metadata before updating any “latest release” statement.
6. Confirm repository ownership/upstream contribution boundaries before representing this repository as the canonical or personally maintained project.

## Verification gaps and risks

- No Swift build, tests, smoke test, hardware probe, signing/notarisation check or release workflow was run for this draft.
- README feature and distribution statements are documentation at the observed source revision; they do not prove the present public release or installation state.
- Local and community hardware coverage may not generalise to every Mac, port controller, cable or charger.
- Some source data may contain user-contributed identifiers; do not copy individual cable fingerprints or contributor details into this plan.

## Source documents

- [README.md](README.md)
- [Translations guidance](TRANSLATIONS.md)
- [Contributors](CONTRIBUTORS.md)
- [Release note v0.5.13](release-notes/v0.5.13.md)
