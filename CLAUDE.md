# Melati - project instructions

Private journaling app (macOS + iOS, SwiftUI). Local SQLCipher database is the
source of truth; CloudKit private-database sync. One XcodeGen project under
`apple/` (shared core + per-platform targets). Min macOS 14, iOS 17.

If a local (untracked) `AGENTS.md` exists, it configures a separate read-only
code-review role for a different tool - it does not apply to sessions working
from this file.

## Build and test

- The Xcode project is generated: run `xcodegen` in `apple/` first, and again
  after every branch switch (stale projects produce phantom failures). Never
  hand-edit the `.xcodeproj`.
- Mac tests (from `apple/`):
  `xcodebuild -project Melati.xcodeproj -scheme Melati -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO test`
- iOS tests: scheme `MelatiIOS`, destination = first available iPhone simulator.
- On a developer machine, ALWAYS add a scratch `-derivedDataPath` to
  signing-disabled invocations. Without it the unsigned test build replaces the
  default-DerivedData Debug app (the copy LaunchServices/Spotlight launches),
  which then crashes at startup (`CKContainer` init traps without iCloud
  entitlements).
- Unit tests are hostless on purpose (no TEST_HOST); a test that launches the
  real app is a bug. Simulator app LAUNCHES need signed builds; only hostless
  test bundles run unsigned.
- `MelatiUITests` is a local-only scheme (needs signing + a one-time macOS
  UI-automation grant). Never add it to CI.
- The editor webview bundle is generated from `apple/editor-embed`; edit
  sources, rebuild, and commit both together (CI has a drift check).
- Never run two app instances against the same database file.
- App icons: SVGs are source of truth, PNGs via `rsvg-convert`; the 1024px iOS
  icon must stay alpha-free.

## Test seams (DEBUG-only, sync-gated)

- `MELATI_TEST_DB_DIR` / `MELATI_TEST_SEED` env vars: isolated database with a
  throwaway key, sync disabled, deterministic pre-seeded entries. ALL E2E and
  manual testing runs through these - never against a real diary. These must
  never become reachable in Release builds, and a test database must never be
  able to sync.
- `-melati.resetSyncState YES` launch argument: one-shot sync-state repair hook.

## Design invariants (do not "fix" these)

- Past entries are immutable - only today's entry is editable, however it is
  reached (paper-diary principle). Deleting old entries may come later; editing
  them never will.
- CloudKit is the app's only network destination. No telemetry, analytics,
  crash reporting, or background update polling - ever. Any new network contact
  must be strictly user-initiated.
- User data (content, location) lives ONLY in `CKRecord.encryptedValues`;
  `schemaVersion` is the only plain field. Test-enforced.
- Entry previews are opt-in and default OFF; "entry content" includes the
  location field. Privacy gates extend to accessibility surfaces: visually
  hidden content must be absent from AX, visible content mirrored to it
  (via `accessibilityValue` - AX drops these Buttons' child Texts from labels).
- The sidebar never overlays an open entry (structural gate, not timing).
- `modified_at` stamps are strictly monotonic; no-op saves (blur, tab switch)
  must not re-stamp. Sync reconciliation is a deterministic three-way merge.
- Debug builds stay on the CloudKit Development environment; Production is
  injected at export time only, never in project entitlements.

## Git

- `main` is branch-protected: all changes land via PR with green CI.
- CI runs unsigned (`CODE_SIGNING_ALLOWED=NO`); don't add jobs that require
  signing or interactive grants.
