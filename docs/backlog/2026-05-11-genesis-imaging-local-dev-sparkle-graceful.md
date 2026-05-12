---
created: 2026-05-11
status: DEFER
owner: null
due: null
---

# Genesis Imaging: local-dev Sparkle init graceful skip

**Why deferred:** Production DMG works perfectly (CI sets `SU_PUBLIC_KEY` env →
`scripts/package-app.sh` writes `SUFeedURL` + `SUPublicEDKey` to Info.plist →
Sparkle auto-check finds the URL on launch). Local-build flow (`swift build
-c release && ./scripts/package-app.sh` without env) leaves Sparkle keys out
of Info.plist; on launch Sparkle's `startingUpdater: true` immediately throws
"You must specify the URL of the appcast as the SUFeedURL key in either the
Info.plist…" dialog. Annoying for local smoke testing but not a real bug —
no production user sees it. Deferred because:

1. CI-built DMG is the canonical install path for end-users
2. Local-build is dev-only context, devs can dismiss the error
3. Fix is mechanical but touches both `scripts/package-app.sh` (always-on
   SUFeedURL with placeholder when keys missing) AND `ImageUpscaleApp.swift`
   (conditional updater init based on Info.plist key presence) — non-trivial
   scope for a non-blocking annoyance

**Pickup conditions:**
- Anyone running automated local-build smoke (CI-like harness that opens
  the local `.app`) — Sparkle error blocks the test runner
- v0.3+ alpha cycle where devs may run local builds frequently
- Adding a "dev mode" / "Skip Sparkle in DEBUG" pattern (cleaner)
- Any session touching `ImageUpscaleApp.swift` Sparkle init

**Implementation sketch:**
- `ImageUpscaleApp.swift` init: check `Bundle.main.object(forInfoDictionaryKey:
  "SUFeedURL")` → if nil, skip `SPUStandardUpdaterController` init entirely
  (or pass `startingUpdater: false`), set updaterController to a no-op stub
- OR `scripts/package-app.sh`: always write `SUFeedURL` (use the canonical
  apps.softwareasan.ai URL as default even without `SU_PUBLIC_KEY`); Sparkle
  will surface signature mismatch later on check, not at launch

**Related work:**
- `Sources/AppShell/ImageUpscaleApp.swift` — updaterController init point
- `scripts/package-app.sh` — `SPARKLE_PLIST_BLOCK` conditional (`SU_PUBLIC_KEY` gate)
- `.github/workflows/release.yml` — CI env setup (no change needed)
- Cross-ref: wisdom_639cbae4 (DMG-installed smoke mandatory) — this fix
  improves the local-build branch of that smoke discipline

**Last touched:** 2026-05-11 (S57 distribution sub-cycle, surfaced during Wave 3 batch upscale smoke)
