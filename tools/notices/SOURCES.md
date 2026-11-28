# Licence texts for the Sentry native parts

Read at build time only by `tools/notices.gd` (the export leaves `tools/` out of the pack). Byte for byte from
upstream, plain `curl`, fetched 28 Nov 2026.

| File | URL | Ref | sha256 |
|---|---|---|---|
| `sentry-native.LICENSE` | https://raw.githubusercontent.com/getsentry/sentry-native/0.17.6/LICENSE | tag `0.17.6` | `5ef07a3d95f1f779c1597c0fbaecbb7ba242128ff0587ed1e3214c7ac6154523` |
| `crashpad.LICENSE` | https://raw.githubusercontent.com/getsentry/crashpad/getsentry/LICENSE | branch `getsentry` (Sentry's Crashpad fork; a moving ref, no tag pinned) | `cfc7749b96f63bd31c3c42b5c471bf756814053e847c10f3eb003417bc523d30` |

Why 0.17.6: Sentry for Godot's CHANGELOG.md (tag `2.5.1`) bumps the Native SDK to v0.17.6 in 2.5.0 and does not
bump it again in 2.5.1. When the addon is updated, re-check its CHANGELOG, fetch again and update this table.
