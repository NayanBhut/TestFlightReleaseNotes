# App Submission Beginner Guide

This guide is for someone publishing an Apple-platform app for the first time. It separates the work Shipyard can help with from the steps that must still be completed in Xcode, App Store Connect, or the Apple Developer portal.

## Before You Start

- Join the [Apple Developer Program](https://developer.apple.com/help/account/membership/programs-overview). A free developer account can test on personal devices, but program membership is required to distribute through the App Store.
- Make sure the Account Holder has accepted Apple's latest agreements. A paid app also requires the Paid Apps Agreement, tax forms, and banking information.
- Install a current version of Xcode and prepare a release-quality app build.
- Decide who owns each responsibility. App creation and submission normally require the Account Holder, Admin, or App Manager role.
- When connecting Shipyard, select the API key type and role shown in App Store Connect. The `.p8` file itself does not reveal its permissions.

## 1. Create the App Identity

1. Choose a permanent bundle identifier, such as `com.company.product`.
2. Create an explicit Bundle ID in Certificates, Identifiers & Profiles.
3. Enable only the capabilities the app actually uses, such as Push Notifications, Sign in with Apple, associated domains, or Apple Pay.
4. Create the required distribution certificate and provisioning profile, or let Xcode manage signing.
5. Keep the bundle identifier in Xcode exactly the same as the identifier registered with Apple.

Shipyard can manage certificates, identifiers, Bundle IDs, devices, and provisioning profiles for the selected team. Xcode remains responsible for compiling, signing, archiving, and uploading the app binary.

## 2. Create the App Store Connect Record

Create the app record before uploading the first build. Follow Apple's [Add a new app](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/) instructions and provide:

- Platform
- App name
- Primary language
- Bundle ID
- SKU (an internal identifier that customers do not see)
- User access, if your organization restricts access

The Bundle ID cannot be changed after the app record is created, so verify the selected team and identifier first.

## 3. Prepare and Upload a Build

In Xcode:

1. Set the marketing version, for example `1.0`, and increment the build number.
2. Add the final app icon and verify all required icon slots.
3. Confirm signing, entitlements, capabilities, and the release configuration.
4. Test the archive on supported devices and check accessibility, privacy prompts, deep links, purchases, and account flows.
5. Archive the app and upload it with Xcode Organizer or another method listed in Apple's [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/) guide.
6. Wait for Apple to finish processing the build before selecting it for the App Store version.

Shipyard can display and select processed builds. It does not currently compile or upload an app binary.

## 4. Complete App Information

Complete the app-level information:

- App name and subtitle
- Primary and secondary categories
- Content rights
- Age rating questionnaire
- Privacy policy URL
- App privacy data-collection answers
- Distribution method
- Price, tax category, and territory availability

Use Apple's references for [required metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/), [app privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy), and [age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating).

## 5. Complete Version Information

For every locale you publish, review and complete:

- Description
- Keywords
- Support URL
- Marketing URL, if used
- Promotional text, if used
- What's New text for app updates
- Screenshots for each required device family and display size

Apple allows 1–10 screenshots for a supported device size. Images must match Apple's dimensions and must not contain transparency. See [Upload app previews and screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/) and [Screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/app-information/screenshot-specifications).

Shipyard can edit localized metadata and screenshots exposed by the App Store Connect API. Always verify every locale before submission, especially right-to-left text and locale-specific URLs.

## 6. Supply App Review Information

Prepare information that lets App Review test every important feature:

- A contact name, phone number, and email address
- Review notes explaining non-obvious flows, hardware requirements, or special setup
- A working demo account when sign-in is required
- Credentials or instructions for role-specific areas
- Attachment details when supporting files are needed

Do not provide expiring credentials unless you can keep them valid throughout review. Explain purchases, subscriptions, location behavior, background modes, encryption, and any unusual entitlement use.

## 7. Answer Compliance Questions

- Complete export-compliance questions for encryption. Apple's [export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/) explains when documentation may be required.
- Complete advertising identifier questions if the app uses tracking or ad attribution.
- Declare content rights and third-party content accurately.
- Verify that privacy labels match the app and every included third-party SDK.
- Review the current [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/).

## 8. Configure Pricing and Availability

- Choose a price, including Free, and select the correct tax category.
- Select countries and regions where the app will be available.
- Choose public, private, or eligible unlisted distribution deliberately; changing between public and private after approval may require a new app record.
- For paid apps or in-app purchases, complete the Paid Apps Agreement, tax, and banking setup.

See Apple's [publishing overview](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store), [pricing instructions](https://developer.apple.com/help/app-store-connect/manage-app-pricing/set-a-price/), and [distribution methods](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/set-distribution-methods).

## 9. Final Preflight

Before selecting **Submit for Review**, confirm:

- The correct team, app, platform, and version are open.
- The selected build has finished processing and matches the version number.
- All required fields are complete in every enabled locale.
- Screenshots are assigned to the correct device sizes.
- App privacy, age rating, pricing, tax category, and availability are complete.
- Review contact information and demo credentials work.
- Export-compliance answers are complete.
- The app has been tested from a clean installation and follows the App Review Guidelines.
- The release method is correct: manual, automatic, or phased release.

Then follow Apple's [Submit an app](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/) instructions. After submission, monitor the version status and respond to App Review messages in App Store Connect.

## Shipyard Scope

| Task | Shipyard | Apple/Xcode |
| --- | --- | --- |
| Manage teams and API credentials | Yes | Create the API key in App Store Connect |
| Certificates, identifiers, devices, profiles | Yes | Also available in the Developer portal |
| Create the app record | No current Shipyard UI | App Store Connect |
| Edit localized app/version metadata | Yes | App Store Connect is the fallback |
| Manage screenshots | Yes, where exposed by the API | Capture/prepare images outside Shipyard |
| Build, archive, sign, and upload binary | No | Xcode/Transporter |
| Privacy questionnaire, agreements, tax, banking | Not all operations | App Store Connect |
| Submit and monitor review | Use Shipyard only where the action is available and verified | App Store Connect remains the source of truth |

## Official Apple References

- [Apple Developer Program overview](https://developer.apple.com/help/account/membership/programs-overview)
- [Create an App Store Connect app record](https://developer.apple.com/help/app-store-connect/create-an-app-record/add-a-new-app/)
- [Upload builds](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
- [Required app metadata](https://developer.apple.com/help/app-store-connect/reference/app-information/required-localizable-and-editable-properties/)
- [App privacy](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy)
- [Age ratings](https://developer.apple.com/help/app-store-connect/manage-app-information/set-an-app-age-rating)
- [Screenshots](https://developer.apple.com/help/app-store-connect/manage-app-information/upload-app-previews-and-screenshots/)
- [Publishing overview](https://developer.apple.com/help/app-store-connect/manage-your-apps-availability/overview-of-publishing-your-app-on-the-app-store)
- [Submit for review](https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-app/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Connect API documentation](https://developer.apple.com/documentation/appstoreconnectapi)
