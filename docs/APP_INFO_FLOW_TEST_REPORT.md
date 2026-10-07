# App Info Flow Test Report

**Date:** 2026-10-07  
**Scope:** App detail `App Info` tab in the Shipyard SwiftUI shell.  
**Status:** First-open blank metadata bug is fixed and live verified through macOS accessibility.

## Bug Reproduced

Opening `SmartClean AI` and navigating to `App Info` for the first time showed an empty metadata form. The form stayed blank because the view created empty drafts before App Store Connect metadata finished loading, then treated those empty strings as user-edited values.

## Fix Summary

- `ShipyardAppInfoView` now activates the selected app before requesting App Info data.
- The selected App Store version localization is loaded on first entry even when a version was already selected by another tab.
- Draft values no longer seed from empty loading state. Untouched fields continue following server values when async App Info and version localization responses arrive.
- Support URL is disabled until the matching version localization exists.
- The save gate now allows general App Info fields to save when only the App Info localization exists.

## Live Accessibility Verification

| ID | Scenario | Result |
| --- | --- | --- |
| INFO-01 | Launch rebuilt Shipyard, open `SmartClean AI`, click `App Info` before visiting `App Store Versions`. | Passed. App Info populated on first open with `SmartClean AI`, `Cleaner`, description text, promo text, URLs, and screenshots section. |
| INFO-02 | Wait after initial App Info open while localization calls complete. | Passed. Version-localized fields became editable after localization data loaded; no permanent blank state. |
| INFO-03 | Navigate from `App Store Versions` back to `App Info`. | Passed. Metadata populated immediately and did not regress to blank fields. |
| INFO-04 | Add localizations and attach test screenshots. | Passed live. Added `en-GB`, `de-DE`, `fr-FR`, `es-ES`, and RTL locale `ar-SA`; created `iPhone 6.7"` screenshot sets for `es-ES` and `ar-SA`; attached `shipyard-appinfo-test.png` and `shipyard-submission-test.png` to both screenshot sets. Manual reload showed `es-ES` and `ar-SA` with 2 images each. |

## Remaining Follow-Ups

- Add an automated regression test for first-open App Info hydration.
- Add a team-switch regression test that starts from App Info and verifies the old app/team data is cleared.
- Consider a visible loading skeleton for version-localized fields so users see that data is still loading, not missing.
- Verify whether screenshots that remain labeled `PENDING` in the manager are expected Apple processing state or an upload-complete status mapping issue.
