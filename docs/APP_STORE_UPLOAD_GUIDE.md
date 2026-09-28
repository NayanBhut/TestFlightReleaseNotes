# App Store Upload Workflow

This guide explains how to prepare and submit an App Store version in this app. The same guide is available in the app at **App Info → Info**.

## Before You Start

Use an App Store Connect API key with the **App Manager** or **Admin** role. A TestFlight-only key can read builds and manage TestFlight release notes, but it cannot create versions, attach builds, edit store metadata, upload screenshots, configure releases, or submit versions for review.

## Upload Workflow

1. **Upload the binary.** Upload the app from Xcode Organizer or App Store Connect and wait until the build reaches `VALID`. This app manages the uploaded build; it does not upload the binary itself.
2. **Open App Info.** Select the app and open the **App Info** tab.
3. **Create the version.** In **App Store Versions**, click **Create New Version**. This button appears only when a live version exists and no pending version is in flight. Enter the version string, platform, copyright, release type, date, and optional build number.
4. **Attach the build.** In the displayed version, choose an eligible build and click **Attach selected build**. Use **Replace build** only when Apple allows changing the attached build.
5. **Complete version metadata.** In **Version Localizations**, add each locale and edit its description, keywords, promotional text, What's New, marketing URL, and support URL.
6. **Upload screenshots.** In a version localization, click **Screenshots**, create a screenshot set, select its display type, and upload images.
7. **Check app information and compliance.** Review **App Store Info** and confirm the **Export Compliance** declaration.
8. **Choose release behavior.** Under **Release Settings**, select Manual, After Approval, or Scheduled, then click **Save release settings**.
9. **Optionally configure phased release.** Under **Phased Release**, click **Start**. Use **Pause**, **Resume**, and **Complete** while the phased release is active.
10. **Submit for review.** Open the **Reviews** tab. In **Review Submissions**, click **Submit for Review** after the version has an attached build.
11. **Release after approval.** For an approved manual release, return to **App Info → App Store Versions** and click **Release This Version**. After Approval and Scheduled releases do not use this button.
12. **Clear a pending version.** If a draft or rejected version is no longer useful, click **Delete Pending Version**. Only one pending version can exist at a time.

## Version Case Logic

The **App Store Versions** card resolves the case from the live and pending versions for the selected platform:

| Case | Condition | Rendering | Create New Version |
|---|---|---|---|
| **BOTH** | Live and pending versions exist | Shows both cards; the pending card shows its specific status label | Hidden |
| **LIVE_ONLY** | Live version exists, no pending version | Shows the live version card | Shown and enabled |
| **PENDING_ONLY** | No live version, one pending version exists | Shows the pending card with its status label | Hidden |
| **NO_VERSION** | No live and no pending version | Shows the empty state prompting first-version creation in App Store Connect | Hidden |

The pending version card uses these labels:

| `appStoreState` | Label |
|---|---|
| `PREPARE_FOR_SUBMISSION` | Draft |
| `WAITING_FOR_REVIEW` | Waiting for Review |
| `IN_REVIEW` | In Review |
| `PENDING_DEVELOPER_RELEASE` | Approved – Ready to Release |
| `REJECTED`, `DEVELOPER_REJECTED` | Rejected |
| `METADATA_REJECTED` | Metadata Rejected |
| `INVALID_BINARY` | Invalid Binary – Needs New Build |
| `PENDING_CONTRACT` | Pending Contract |
| `PROCESSING_FOR_DISTRIBUTION` | Processing |

`REPLACED_WITH_NEW_VERSION` and `REMOVED_FROM_SALE` are ignored. If the API unexpectedly returns more than one pending version, the most recently created is used and a warning is logged.

Only `PREPARE_FOR_SUBMISSION`, `REJECTED`, `DEVELOPER_REJECTED`, `METADATA_REJECTED`, and `INVALID_BINARY` are editable. All other states are read-only, including builds, localizations, screenshots, and release settings. When no editable pending version exists (for example, a live-only app), the **Edit**, **Screenshots**, and **Add Localization** buttons are hidden.

Build selection, localizations, screenshots, release settings, and phased release target the pending version when one exists; otherwise they target the live version.

## Screenshot Upload and Data

Screenshots have their own **Screenshots** section on the main App Info view, grouped by version and locale:

1. The **Screenshots** section lists each locale of the current version, with an image count and an inline thumbnail strip that loads on appear.
2. When a locale has no screenshots of its own, the row shows a **USING `<primary locale>`** chip and explains that the App Store is serving the primary-locale images for that locale, instead of a bare "no screenshots" message.
2. In the **BOTH** case, the live version is listed first as a read-only group so its screenshots stay visible.
3. Click **Manage** on a locale row to open the screenshots sheet for that locale, where you can switch sets, create sets, upload, and delete.
4. **Screenshot Sets** lists `AppScreenshotSetModel` records grouped by display type. Click **Select** to switch sets, choose a **Display type**, then click **New Set**.
5. **Screenshots** lists the `AppScreenshotModel` records of the selected set as thumbnails, with **Delete** per screenshot.
6. Upload images with the file picker. Uploads follow Apple’s reserve → `PUT` upload operations → commit pipeline, after which the set reloads.

API routes used:

| Purpose | Route |
|---|---|
| List sets for a locale | `GET /v1/appStoreVersionLocalizations/{id}/appScreenshotSets` |
| Create a set | `POST /v1/appScreenshotSets` |
| List screenshots in a set | `GET /v1/appScreenshotSets/{id}/appScreenshots` |
| Upload a screenshot | `POST /v1/appScreenshotSets/{id}/appScreenshots` plus reserved upload operations |
| Delete a screenshot | `DELETE /v1/appScreenshots/{id}` |

The **Screenshots** section and its **Manage** button stay available in every case, including live-only and the live version inside **BOTH**, so already-uploaded images remain visible. When the version is not editable, the sheet is read-only: sets and thumbnails load normally, while **New Set**, **Upload Image**, and per-screenshot **Delete** are hidden. **Edit** and **Add Localization** are hidden in that state.

## Button and Section Guide

| Button or section | Location | Purpose |
|---|---|---|
| **Info** | App Info header | Opens the in-app upload guide. |
| **Refresh** | App Info header | Reloads App Info and version-scoped data. |
| **Create New Version** | App Store Versions | Creates a version from a live version. Only shown in the live-only case. |
| **Attach selected build** | Pending App Store version | Attaches the chosen valid build. |
| **Replace build** | Pending App Store version | Replaces the attached build when editable. |
| **Delete Pending Version** | Pending App Store version | Deletes a draft or rejected pending version. |
| **Add Localization** | Version Localizations | Creates a localization for the displayed version. Hidden when read-only. |
| **Edit** | App/version localization rows | Edits app or version-localization metadata. Hidden when read-only. |
| **Screenshots** (section) | App Info | Inline screenshot thumbnails per version and locale, with image counts. |
| **Manage** | Screenshots section | Opens the screenshots sheet for one locale. Read-only when the version is not editable. |
| **Live Version Localizations** | App Info | Read-only localizations for the live version when both live and pending versions exist. |
| **Select / New Set / Delete** | Screenshots sheet | Switches sets, creates a set for a display type, or removes a screenshot. New Set and Delete are hidden when read-only. |
| **Save release settings** | Release Settings | Saves release type, date, and copyright. |
| **Start / Pause / Resume / Complete** | Phased Release | Controls the phased rollout. |
| **Release This Version** | App Store Versions | Releases an approved manual version. Shown only for `PENDING_DEVELOPER_RELEASE` manual versions. |
| **Submit for Review** | Reviews → Review Submissions | Sends the attached App Store version for review. |
| **Cancel Submission** | Reviews → Review Submissions | Cancels a review submission when Apple permits it. |
| **Export Compliance** | App Info | Shows encryption and export declarations. |

## Release Types

- **Manual:** Wait for approval, return to App Info, and click **Release This Version**.
- **After Approval:** Apple releases the version automatically after approval.
- **Scheduled:** Choose the earliest release date before submission.

Once distribution has started, the version is locked. Only one pending version may exist at a time, so release, finish, or delete it before creating another version.

## Safety Notes

- A build must be `VALID`, unexpired, and match both the version string and platform before it can be attached.
- Confirm destructive actions such as **Delete Pending Version**, **Release This Version**, **Complete** phased release, **Delete** screenshots, and **Cancel Submission**.
- Permission failures should be reported as an App Manager/Admin API-key requirement rather than repeated without changes.
