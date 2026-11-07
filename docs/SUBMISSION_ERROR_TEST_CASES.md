# Structured submission errors

Shipyard preserves the complete JSON error body and HTTP status. Associated errors
are recursively flattened ahead of their parent, with duplicates removed from the
visible list. Copy technical details retains the original errors and metadata,
including duplicates, source pointers, resource paths, and Retry-After.

A short ToastCenter summary accompanies the Submission Issues sheet. Unknown
errors keep Apple's exact text and pointer without an invented solution.

## Automated cases

| Case | Expected behavior |
| --- | --- |
| Single top-level error | Original status, code, title, detail, and pointer survive decoding. |
| Nested associated errors | Every child appears before its parent; full resource-path chains survive recursion. |
| Multiple missing fields | Each field has a separate issue. Social Media, other Age Ratings, version localizations, review contact, build, and encryption have the relevant guidance. |
| Unknown code or pointer | Exact Apple detail and pointer remain visible. No speculative solution; an unresolved required pointer blocks retry. |
| Duplicate errors | Identical visible issues collapse; different resources remain separate; original payload remains available to copy. |
| 401 / 403 / 409 | Authentication, submission permissions, and refresh guidance appear with Apple's original detail. |
| 429 | Retry-After supports delay seconds and an HTTP date. Both refresh and retry wait for the deadline. Without a usable header, a clearly labeled 60-second local backoff applies. Elapsed delay still requires refresh and validation. |
| Missing or malformed metadata/body | Useful outer errors remain readable; malformed raw response remains available in technical details. |
| Retry before refresh | UI disabled; coordinator also rejects the call without making a request. |
| Successful refresh | Reads fresh version state, selected build eligibility, localizations, review contact/demo requirements, scheduled release date, named required fields, and partial submission state. Performs no writes. |
| Missing prerequisites / failed refresh | Explains what remains unresolved and leaves retry disabled. A saved `false` questionnaire answer counts as present. |
| Partial submission | Reuses the known draft and confirms linked items; retry does not create a duplicate draft or item. |
| Ambiguous write timeout | Does not blindly create another draft or link. Requires reconciliation; unresolved creation remains blocked for inspection in App Store Connect. |
| Dismiss and reopen | Same failure and retry gate remain; reopening cannot bypass refresh. |
| Context changes during refresh | Stale responses cannot arm retry for another app/team. |
| Untrusted associated resource path | Only explicit App Store Connect v1 resource routes are read; external/unknown paths are not followed. |

Unit cases and JSON fixtures live in `SubmissionIssuesTests.swift` and
`SubmissionTestFixtures.swift`. UI cases in `ReviewSubmissionUITests.swift` render
the actual release dialog with an in-memory transport. Launch requires
`SHIPYARD_REVIEW_UI_TESTS=1` and a recognized scenario; APIClient and URLProtocol
reject HTTP(S), credentials are never loaded, and external links are disabled.
The fixture transport throws on any unexpected request. The shared scheme’s Test
Action also launches the unit-test host in fixture mode, so normal test runs do
not load production credentials or wait for Keychain access. No submission is
made to Apple.

## Verification commands

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"
xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" build -skipMacroValidation
xcodebuild test -project "App Store.xcodeproj" -scheme "App Store" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -skipMacroValidation '-only-testing:App Store Tests/SubmissionIssuesTests'
```

Run the five `testSubmission…` UI methods using the UI-test target. Local macOS
runner signing/launch permissions may require a development-signed runner. Keep
any local test artifact signing changes out of production target settings.

## Verified results (2026-11-07)

- 250 unit tests passed, including 23 submission issue/transaction tests.
- All 25 UI cases passed across the full suite and the focused rerun after fixing
  XCTest's long-text query limit; five cases cover the new submission sheet.
- The generated shared-scheme configuration was separately verified without
  environment overrides: all 23 submission unit tests and the fail-closed UI
  launch test passed.
- Required `plutil` and the exact unsigned Debug build command above passed.
- Native tests used offline fixtures; no live submission or App Store write was performed.
