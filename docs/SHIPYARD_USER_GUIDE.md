# Shipyard User Guide

This is the complete user guide for Shipyard. It explains how to connect an Apple Developer team, navigate the app, use every available feature, understand status and feedback, and know when a task must be completed in Xcode, App Store Connect, or the Apple Developer website.

For a first App Store submission checklist, also read [App Submission Beginner Guide](APP_SUBMISSION_BEGINNER_GUIDE.md).

## What Shipyard Is

Shipyard is a native macOS client for Apple Developer resources and the App Store Connect API. It brings app metadata, versions, builds, TestFlight information, customer reviews, signing resources, users, and locally observed monitoring into one interface.

Shipyard can:

- Connect multiple App Store Connect teams securely through API keys stored in macOS Keychain.
- Browse apps, App Store versions, builds, and processing status.
- Edit app metadata, localized metadata, release notes, and screenshots where Apple permits API changes.
- Prepare App Store versions, select builds, save review information, submit, cancel eligible submissions, and release eligible versions.
- View customer reviews and send developer replies.
- Manage TestFlight release notes, beta groups, testers, and build assignments.
- Register and manage devices.
- Create, inspect, download, and revoke certificates.
- Create Merchant IDs and Pass Type IDs.
- Register and manage Bundle IDs and capabilities.
- Create, inspect, download, install, delete, and regenerate provisioning profiles.
- Invite, edit, and remove team users and manage pending invitations.
- Monitor processing builds and local certificate/profile expiry reminders.

Shipyard does not compile, archive, sign, or upload an app binary. Use Xcode Organizer, Transporter, or another Apple-supported upload tool for binary uploads.

## Roles and Permissions

An API key can only perform actions allowed by its App Store Connect role. A screen may load successfully while a write action fails because the key has read-only or narrower permissions.

Typical permission levels:

- **Developer or TestFlight access:** builds, TestFlight metadata, and related reads where granted.
- **App Manager or higher:** most app metadata and App Store version writes.
- **Admin:** signing resources, users, invitations, and wider team management.
- **Account Holder:** agreements and certain organization-level decisions that an API key cannot replace.

When Shipyard shows a permission error, use an API key with the required role rather than repeatedly retrying the same operation.

### API Key Type, Role, and Visibility

The `.p8` private key does not contain a readable App Store Connect role. A signed JWT also identifies the key but does not include a trustworthy role claim that Shipyard can use for navigation. When adding a team, select the key type and access role exactly as configured in App Store Connect.

Apple's [API key documentation](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api) supports two key types, while the detailed [role permissions matrix](https://developer.apple.com/help/account/access/roles) remains the source of truth for permitted operations:

- **Team Key:** assigned one role when generated and available across all apps on the account. Its role cannot be edited after creation; revoke and replace the key to change it.
- **Individual Key:** inherits the associated user's roles and app access. Apple does not allow individual keys to use provisioning endpoints.

Shipyard uses the declared key type and role only to hide unrelated navigation. It is not a security boundary and does not grant access. Apple evaluates every API request, and a 403 response overrides the configured visibility.

Current visibility presets:

| Declared access | Shipyard areas shown |
| --- | --- |
| Admin Team Key | Builds, App Info, Reviews, App Store Versions, Monitoring, Devices, Certificates, Identifiers, Bundle IDs, Profiles, Users |
| Admin Individual Key | Builds, App Info, Reviews, App Store Versions, Monitoring, Users; provisioning-resource screens remain hidden |
| App Manager | Builds, App Info, Reviews, App Store Versions, Monitoring |
| Developer | Builds, App Store Versions, Monitoring |
| Marketing | App Info |
| Customer Support | Reviews |
| Finance or Sales | Apps list only; Shipyard does not currently provide finance or sales-reporting features |
| Access not configured | All navigation remains visible for backward compatibility |

Apps always remains visible so the connection can be validated and app-scoped access can be understood. Individual keys may still see only the apps assigned to their user.

To change the declared visibility for an existing connection, open **Settings → Teams**, switch to the team, and choose **Key Type** and **Access Role**. Select **Clear** to return to the backward-compatible mode that shows all navigation.

## Connect Your First Team

Before starting, create an App Store Connect API key from **Users and Access → Integrations → App Store Connect API**. Record its Issuer ID and Key ID, and download the `.p8` private key. Apple only allows the private key file to be downloaded once.

In Shipyard:

1. Open the app and select **Add App Store Connect API Key**.
2. Enter a unique local **Team Name**. This is the label Shipyard displays in the team selector.
3. Enter the **Issuer ID** and **Key ID** exactly as shown by Apple.
4. Select whether this is a Team Key or Individual Key and choose its configured role.
5. Choose the `.p8` file or paste its key contents.
6. Continue to verification. Shipyard contacts App Store Connect and checks whether apps can be read.
7. Select **Add Team** after verification succeeds.

Credentials and private keys are stored in macOS Keychain and should never be pasted into logs, screenshots, bug reports, or documentation.

### Add Another Team

1. Open the team selector at the top of the sidebar.
2. Select **Add Team**.
3. Complete the same five-step connection assistant.

### Switch Teams

1. Open the team selector.
2. Select the required team.
3. Wait while Shipyard clears app-specific selections and reloads data for the new team.

Always verify the active team before creating, modifying, revoking, or deleting anything. Team resources are real Apple Developer data.

### Remove a Team

1. Open the team selector.
2. Use the remove control beside the team.
3. Confirm **Remove Team**.

This removes that team's credentials from the local Keychain. It does not delete the Apple Developer team or revoke the API key on Apple's website.

## Window and Navigation

The window has two main areas:

- **Sidebar:** team selection, top-level sections, Settings, and Help.
- **Content area:** lists, inspectors, app details, forms, and operation results.

The sidebar contains:

- **Apps**
- **Processing Builds**
- **Devices**
- **Certificates**
- **Identifiers**
- **Bundle IDs**
- **Profiles**
- **Users**

Builds, App Info, Reviews, and App Store Versions are app-specific and appear after opening an app. Reviews are not repeated in the global sidebar because they require an app context.

### Back Navigation

- **Apps** in an app or build toolbar returns to the apps table.
- **Builds** in build detail returns to the selected app's builds.
- **Versions** in version detail returns to the App Store Versions list.
- Switching a top-level sidebar section closes app and build detail screens.
- Cross-resource links, such as **Open Profile**, move to the destination section and apply a search when possible.

### Loading, Errors, and Results

- A progress indicator means Shipyard is waiting for Apple or loading another page.
- **Retry** repeats the failed read with the current team and selection.
- **Load More** retrieves the next Apple pagination page.
- Success and failure toasts appear at the lower-right after write operations.
- Confirmation sheets explain destructive effects before a revoke, delete, disable, expire, or submission action.
- If a cached snapshot is marked stale, refresh before editing. Shipyard may disable writes until a fresh read succeeds.

## Apps

Open **Apps** from the sidebar to see apps available to the active API key.

Available actions:

- Search by app name or related visible identifiers.
- Filter by app state.
- Sort the loaded apps.
- Refresh or retry the list.
- Load additional pages.
- Open an app by selecting its row.

The table shows the icon, app name, Bundle ID, Apple ID, state, and platform when available.

Shipyard does not currently create a new App Store Connect app record. Create the record in App Store Connect, then refresh **Apps** in Shipyard.

## App Detail

Selecting an app opens four tabs:

- **Builds**
- **App Info**
- **Reviews**
- **App Store Versions**

The toolbar shows the app name and Bundle ID. Select **Apps** to return to the app list.

## Builds and TestFlight

Open **Apps → select an app → Builds**.

### Browse Builds

- Use the version picker beside the app name to choose a pre-release version.
- Use **Filter Status** to show a processing state such as Processing or Valid.
- Use the refresh button to request current build data.
- Review build number, marketing version, upload date, processing state, and expiration.
- Select **Manage** to open build detail.

Only builds uploaded to Apple appear here. Upload binaries outside Shipyard and wait for Apple processing.

### TestFlight Release Notes

Each build row can show compact TestFlight notes:

1. Select **Notes** to expand the editor.
2. Select an existing locale chip or use the locale picker to add another locale.
3. Enter the TestFlight note for that locale.
4. Select **Save Notes**.
5. Use **Revert** to discard the local draft or **Remove** to delete that localization.

These notes are TestFlight `betaBuildLocalizations`. They are different from the App Store version's **What's New** text.

### Build Detail

Select **Manage** on a build. Build detail contains:

- **Release Notes:** localized TestFlight notes.
- **Compliance:** export-compliance information available for the app/build.
- **Groups:** beta groups, testers, and assigned builds.
- Build metadata and App Store Connect identifiers.
- **Expire Build**, when Apple permits it.

Expiring a build is destructive for testing access. Testers lose access immediately.

### Beta Groups and Testers

In build detail, open **Groups**.

Available operations include:

- Browse beta groups.
- View group testers and assigned builds.
- Add testers to a group.
- Remove a tester from the selected group.
- Delete a tester from the team.
- Assign a build to a group.
- Delete a beta group.

External testing can require Apple Beta App Review. Removing a tester from a group is different from deleting the tester from the entire team.

## App Info

Open **Apps → select an app → App Info**.

App Info loads app-level information, App Store version localization data, and screenshots. Wait for the loading indicators before deciding a field is empty.

### Localizations

- Use the localization menu to switch between existing locales.
- Use **Add** to create another supported localization.
- Use **Remove Localization** to delete the selected non-required localization.
- Select **Save Changes** after editing.
- Right-to-left locales, such as Arabic, use right-to-left text direction in editable fields.

General and localized fields include, where available:

- App name
- Subtitle
- Privacy policy URL
- Support URL
- Description
- Keywords
- Promotional text
- Marketing URL

Shipyard validates Apple's common text limits and accepts only `http` or `https` URLs. A live version is read-only; create or open an editable version before changing locked version metadata.

### Screenshots

The Screenshots area is grouped by version localization and device display type.

Use it to:

- View screenshot sets and thumbnails for the selected locale/version.
- Create a missing screenshot set.
- Upload screenshots to a set.
- Delete screenshots from an editable version.

Read-only versions still show available screenshots but hide write controls. Prepare images in Apple's supported dimensions and without an alpha channel. Screenshot upload may remain in a processing state while Apple validates the asset.

## Customer Reviews

Open **Apps → select an app → Reviews**.

Available operations:

- Filter by star rating.
- Filter by response state.
- Search review content.
- Clear active filters.
- Load additional review pages.
- Read rating, title, body, date, territory, and existing developer response.
- Send a developer reply where Apple permits it.

Customer reviews are public App Store feedback. They are separate from App Review submission messages and rejection conversations.

The Reviews area may also surface eligible review-submission information. For the complete version workflow, use **App Store Versions**.

## App Store Versions and Submission

Open **Apps → select an app → App Store Versions**.

This is the primary release and submission workspace.

### Version List

- Search by version or build.
- Filter by submission/release status.
- Select a version row to open its detail.
- Use **New Version** when the current Apple state permits creating another version.
- Use the back control in version detail to return to the list.

The list is scoped to the selected app and platform. Do not treat every historical version as editable.

### Prepare an Editable Version

For a draft, rejected, metadata-rejected, developer-rejected, or invalid-binary version:

1. Open the version.
2. Choose a processed build that matches the app, platform, and marketing version.
3. Select a locale and enter **What's New** for an update. A first release does not require What's New.
4. Enter App Review contact first name, last name, phone, and email.
5. If sign-in is required, enable the demo-account option and provide working credentials.
6. Add review notes explaining setup, hardware, purchases, or non-obvious behavior.
7. Choose manual, automatic, or scheduled release where available.
8. Save until no unsaved-change warning remains.
9. Select **Submit for Review** and confirm the submission summary.

The build picker shows a loader while matching builds are fetched and an updating state while Apple changes the build relationship. Only valid, unexpired matching builds should be selectable.

### Status-Specific Actions

- **Waiting for Review:** metadata is normally locked; cancel when Apple permits cancellation.
- **In Review:** monitor the state and use App Store Connect for conversations that the public API does not expose.
- **Rejected / Metadata Rejected / Invalid Binary:** read the reason in App Store Connect, correct the required data or build, save, and resubmit.
- **Pending Developer Release:** select **Release This Version** for manual release.
- **Processing for Distribution:** wait for Apple; refreshing cannot accelerate processing.
- **Live:** inspect published information and create a new version for the next update.
- **Removed from Sale:** availability changes may require App Store Connect depending on API support.

The Resolution Center is intentionally not presented as a functional Apple-message inbox because Apple's public API does not provide complete rejection conversations. Use **Open in App Store Connect** for official App Review communication.

## Processing Builds and Monitoring

Open **Processing Builds** from the sidebar.

Shipyard's monitoring is a local observation system. It polls while the app is running and records observed changes; it is not Apple's complete event history.

The alert center can show:

- Builds still processing.
- Locally observed build transitions.
- Certificate expiry reminders.
- Provisioning-profile expiry reminders.
- Read/unread state stored locally.
- Jump actions to Builds, Apps, Certificates, or Profiles.

Use **Monitor Preferences** to configure:

- Whether desktop polling is enabled.
- Active-build polling cadence.
- Which build/review/expiry events are observed.
- Whether expiry reminders are shown.
- Optional macOS notifications.

### Offline and Rate-Limited States

- Offline mode preserves the last successful snapshot and local drafts but blocks network writes.
- **Check Connection** verifies connectivity; it does not guarantee every resource is fresh.
- When Apple rate-limits a scope, Shipyard backs off instead of repeatedly retrying.
- Refresh affected resources after connectivity or authorization is restored.

## Devices

Open **Devices** from the sidebar.

Available operations:

- Search devices.
- Filter by platform.
- Register one device.
- Import devices from CSV or text.
- Open device details.
- Rename a device.
- Enable or disable a device.
- Inspect dependent provisioning profiles.
- Jump to a dependent profile.
- Load additional pages.

### Register a Device

1. Select **Register Device**.
2. Enter a descriptive name.
3. Enter the exact UDID.
4. Select the platform.
5. Review the yearly-limit warning and submit.

Every registration consumes a device slot for the Apple membership year. Disabling a device does not restore that slot, and registered devices cannot be deleted through the API.

### Import Devices

1. Select **Import CSV** from the empty state.
2. Choose a CSV or text file containing one device per line using name, UDID, and platform.
3. Review parsed rows before starting.
4. Confirm the number of real registrations.
5. Review the completion report for registered rows and per-row failures.

### Disable or Enable

Inspect dependent profiles before disabling a device. Existing installed profiles are not automatically rewritten. Regenerate compatible Development or Ad Hoc profiles after changing device eligibility when necessary.

## Certificates

Open **Certificates** from the sidebar.

Available operations:

- Search and browse certificates.
- Inspect certificate details and current status.
- Create a certificate from a CSR.
- Download one or multiple `.cer` files.
- Export a bulk-download result ledger.
- Revoke one or multiple certificates.
- Retry failed local file writes.

### Create a Certificate

1. Prepare a Certificate Signing Request using Keychain Access or another trusted CSR tool.
2. Select **Create Certificate**.
3. Choose the certificate type.
4. Choose the CSR file.
5. For an Apple Pay certificate, select the required Merchant ID.
6. For a Wallet pass certificate, select the required Pass Type ID.
7. Create the certificate.
8. Download the resulting `.cer` and install it into the Keychain that contains the CSR's private key.

Shipyard validates that relationship-based certificate types include the required Apple resource. A typed identifier string is not a substitute for Apple's resource ID.

### Revoke a Certificate

Revocation is irreversible and can invalidate dependent provisioning profiles. Review the impact, confirm deliberately, then recreate or regenerate affected profiles as needed.

## Identifiers

Open **Identifiers** from the sidebar and use the type menu.

### Merchant IDs

- List and search Merchant IDs.
- Create a Merchant ID using a name and unique identifier such as `merchant.com.company.product`.
- Use the resulting Merchant ID when creating an Apple Pay certificate.

### Pass Type IDs

- List and search Pass Type IDs.
- Create a Pass Type ID using a name and unique identifier such as `pass.com.company.product`.
- Use it when creating a Wallet pass certificate.

### App Groups

App Group list/create operations are not exposed by the public App Store Connect API used by Shipyard. Create App Groups in the Apple Developer website, then enable the App Groups capability on the appropriate Bundle ID.

## Bundle IDs

Open **Bundle IDs** from the sidebar.

Available operations:

- Search and browse Bundle IDs.
- Register a Bundle ID.
- Open the Bundle ID inspector.
- Rename its display name.
- Inspect dependent apps and provisioning profiles.
- Enable or disable supported capabilities.
- Delete an unused Bundle ID.
- Select multiple rows and copy identifier information.

### Register a Bundle ID

1. Select **New Bundle ID**.
2. Enter a recognizable name.
3. Enter the exact reverse-DNS identifier used by the Xcode target.
4. Choose the platform and optional seed ID where applicable.
5. Select **Register Bundle ID**.

The identifier string is effectively permanent. Confirm the active team and exact value before registration.

### Capabilities

Open a Bundle ID and select **Enable capability** or disable an existing capability. Capability changes affect entitlements and do not automatically update existing provisioning profiles. Recreate affected profiles after changing capabilities.

### Delete a Bundle ID

Shipyard checks dependent apps and profiles before deletion. If dependencies exist, follow the jump links to resolve them. You must type the identifier to confirm a permitted deletion. Deleting the Bundle ID does not delete an App Store Connect app record.

## Provisioning Profiles

Open **Profiles** from the sidebar.

Available operations:

- Search profiles.
- Filter by profile type and status.
- Create a profile.
- Open a dependency inspector.
- Download one or multiple `.mobileprovision` files.
- Install a profile for Xcode.
- Delete profiles.
- Regenerate invalid or expired profiles.
- Jump to related certificates, Bundle IDs, and devices.

### Create a Profile

1. Select **Create Profile**.
2. Choose the profile type and platform.
3. Enter a profile name.
4. Select a compatible Bundle ID.
5. Select compatible active certificates.
6. Select devices when the profile type requires them.
7. Review the signing chain and create the profile.
8. Download the file or select **Install for Xcode**.

### Inspect a Profile

The inspector shows status, type, platform, expiration, Bundle ID, certificates, devices, profile content availability, and whether matching private keys are available locally.

### Regenerate a Profile

Apple does not expose an update operation for a provisioning profile. Shipyard regeneration deletes the old profile and creates a replacement:

1. Open an invalid or expired profile.
2. Select **Regenerate**.
3. Choose compatible certificates and devices.
4. Review old and replacement dependencies.
5. Select **Delete & Recreate**.
6. Download the replacement and update Xcode and CI references.

This action is destructive. If replacement creation fails after deletion, the old profile cannot be restored through Shipyard.

## Users and Invitations

Open **Users** from the sidebar.

Use the **Members** and **Pending** tabs to separate active users from invitations.

Available operations:

- Search members.
- Invite a user.
- Assign one or more roles.
- Grant access to all apps or selected apps.
- Edit an eligible user's role or app access.
- Remove an eligible user.
- Inspect pending invitations.
- Resend or cancel an invitation.
- Load additional pages.

The Account Holder is read-only in Shipyard and cannot be removed or edited.

### Invite a User

1. Select **Invite User**.
2. Enter first name, last name, and email.
3. Select appropriate roles using least privilege.
4. Choose all-app access or select at least one visible app.
5. Review and send the invitation.

Resend currently revokes the old invitation and creates a new one because Apple provides no dedicated resend endpoint. Read the result carefully if either step fails.

## Settings

Select **Settings** at the bottom of the sidebar.

### General

- Choose the default startup view: Apps, Builds, or Processing Builds.
- Choose the default metadata editing locale.
- Choose whether App Store Connect links open in the external browser.

The default metadata locale controls Shipyard's initial editor selection; it does not change an app's Apple `primaryLocale`.

### Teams

- Review connected local teams.
- See the active team.
- Switch teams.

### Monitoring

- Enable or disable polling.
- Configure polling cadence and monitored event types.
- Configure reminder and notification preferences.

### Notifications

- Open macOS notification settings.
- Review the difference between optional desktop notifications and the in-app alert center.

### Snippets

- Review reusable release-note text.
- Select **Copy**, then paste a snippet into a What's New, description, or TestFlight note field.

### Advanced

- Switch between light and dark appearance.
- Show or hide extended app information, review, and resource surfaces where supported.

## Help

Select **Help** at the bottom of the sidebar for a short first-submission checklist and direct links to official Apple documentation.

The full repository documentation is:

- [Shipyard User Guide](SHIPYARD_USER_GUIDE.md): navigation and every user-facing feature.
- [App Submission Beginner Guide](APP_SUBMISSION_BEGINNER_GUIDE.md): first app and submission prerequisites.
- [Shipyard Engineering and Test Reference](SHIPYARD_REFERENCE.md): implementation, API, and regression details.
- [Shipyard Blockers and Open Bugs](SHIPYARD_BLOCKERS_AND_BUGS.md): known limitations and unresolved issues.

## Common Task Recipes

### Publish an Existing App Update

1. Upload a correctly versioned build using Xcode.
2. In Shipyard, select the correct team.
3. Open **Apps → app → Builds** and wait until the build is valid.
4. Open **App Info** and complete metadata, localizations, and screenshots.
5. Open **App Store Versions** and select or create the update version.
6. Choose the matching build.
7. Complete What's New, review contact, demo account, review notes, and release method.
8. Save all changes.
9. Submit for review.
10. Monitor the version state and use App Store Connect for official review conversations.

### Create Development Signing Resources

1. Open **Bundle IDs** and register or inspect the app's identifier.
2. Enable required capabilities.
3. Open **Devices** and register test devices.
4. Create a CSR on the Mac.
5. Open **Certificates** and create an iOS Development certificate.
6. Install the downloaded `.cer` into the Keychain containing the CSR private key.
7. Open **Profiles** and create an iOS Development profile using the Bundle ID, certificate, and devices.
8. Install the profile for Xcode.

### Create an Apple Pay Certificate

1. Open **Identifiers → Merchant IDs**.
2. Create or locate the correct Merchant ID.
3. Prepare a CSR.
4. Open **Certificates → Create Certificate**.
5. Choose the Apple Pay certificate type.
6. Select the Merchant ID resource.
7. Choose the CSR and create the certificate.
8. Download and install the `.cer`.

### Add a TestFlight Tester to a Build

1. Open **Apps → app → Builds**.
2. Select **Manage** for the build.
3. Open **Groups**.
4. Select the beta group.
5. Add the tester if needed.
6. Assign the build to the group.
7. Complete external-testing review requirements in App Store Connect if Apple requests them.

### Respond to a Customer Review

1. Open **Apps → app → Reviews**.
2. Filter or search for the review.
3. Read the complete review and any existing response.
4. Select **Reply**.
5. Write a concise public response and send it.

### Change Teams Safely

1. Save or discard current drafts.
2. Open the team selector.
3. Select the destination team.
4. Confirm that the sidebar and content reload.
5. Reopen the required app or resource instead of relying on the old selection.

## Safety Rules

- Confirm the active team before every write.
- Use throwaway identifiers only when live testing requires creation.
- Device registrations consume real yearly slots.
- Certificate revocation is irreversible.
- Disabling devices or Bundle ID capabilities can invalidate signing relationships.
- Profile regeneration deletes before recreating.
- Removing users, testers, invitations, identifiers, groups, and profiles changes real Apple data.
- Never assume a timeout means a write failed; refresh before repeating a create or destructive operation.
- Never share Issuer IDs, Key IDs, `.p8` contents, private keys, passwords, or demo credentials in logs.

## Current Boundaries

Complete these tasks outside Shipyard:

- Enroll in the Apple Developer Program.
- Accept legal agreements and complete tax/banking setup.
- Create App Store Connect API keys.
- Create the initial App Store Connect app record.
- Compile, archive, sign, validate, and upload app binaries.
- Create App Groups.
- Complete unsupported privacy, pricing, territory, contract, or compliance operations.
- Read and reply to official App Review rejection conversations when the public API does not expose them.
- Perform any action that Apple restricts to the Account Holder or website UI.

When Shipyard and App Store Connect appear different, refresh Shipyard and treat App Store Connect as the source of truth for Apple's current state.
