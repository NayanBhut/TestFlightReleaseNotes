# Batch J — Validation Scenarios

Manual test scenarios for PR #25 (`feat/batch-j-reapply`). Each feature was
build-verified (`BUILD SUCCEEDED`) and the existing test suite passes; these
scenarios cover the live-API behaviour CI can't.

## How to run the code

```bash
# Worktree (this branch)
cd /Users/nayan.bhut/Desktop/TestFlight/TF-batch-j-reapply
open "App Store.xcodeproj"   # then Run (Cmd+R) in Xcode

# CLI build (no signing)
xcodebuild -project "App Store.xcodeproj" -scheme "App Store" \
  -destination "platform=macOS" CODE_SIGNING_ALLOWED=NO build
```

Writes (submit/cancel, phased release, screenshots, reports) need an API key
with App Manager / Finance roles. A TestFlight-only key must show the
permissions hint — never a crash or a silent no-op.

---

## Reviews — submit / cancel

1. Reviews tab → **Submit for Review** → confirm → new submission row appears after refetch.
2. Cancel button shows only on `READY_FOR_REVIEW` / `WAITING_FOR_REVIEW` rows → confirm → row state updates.
3. TestFlight-only key: submit surfaces the App Manager permissions hint, no crash.

## Reviews — phased release

4. Phased Release card → version picker lists App Store versions → select → state loads (or "Not started").
5. Start → Pause → Resume → Complete (confirm dialog) — state chip updates each step.
6. Switch apps mid-flow → card resets, no stale version/state.

## Reports tab

7. Enter vendor number → Download sales report → save dialog → file written → Show in Finder reveals it; `gunzip` to verify content.
8. Switch Sales ↔ Finance (region ZZ) → correct filters sent.
9. Empty vendor number → inline error, no request. Vendor number persists per team across restarts.
10. Cancel the save dialog → back to idle, no error.

## Screenshots

11. App Info → version localization → Screenshots → sets load (or "No sets yet").
12. New Set with display type → screenshots grid → Upload Image (PNG/JPEG) → progress bar → thumbnail appears UPLOADED.
13. Delete screenshot → confirm → removed from grid.
14. Upload with TestFlight-only key → permissions hint surfaced.

## Events / webhooks + polish

15. App Info → In-App Events and Webhooks cards load (or 403 hint on narrow keys).
16. Version chips: selection pill slides, selected chip auto-scrolls into view.
17. App rows fade highlight on selection; counts tick with numeric transitions.

---

## Next-change candidates (post-merge)

1. Screenshot reorder (PATCH set order) — only write op skipped in F4.
2. Review reply edit — impossible (no PATCH in spec); delete exists if wanted.
3. Sales report charts — parse downloaded gzip TSV, render top-territory/device charts in Reports.
4. In-app events / webhook writes (POST/PATCH) — currently read-only.
5. Scheduled submits — queue a submit/cancel with a local timer + notification.
6. Diff-version compare — side-by-side whatsNew across two builds.