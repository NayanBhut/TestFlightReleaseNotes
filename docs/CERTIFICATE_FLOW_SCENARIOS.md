# Certificate Flow Scenarios

**Last updated:** 2026-10-06

Use this file as the repeatable checklist for future certificate regressions. The live report with observed results is `docs/CERTIFICATE_FLOW_TEST_REPORT.md`.

## Safety Notes

- Certificate creation and revoke are real App Store Connect mutations.
- Revoke is irreversible and invalidates dependent provisioning profiles.
- Use a throwaway CSR and record any created certificate name, id, type, serial, and cleanup result.
- Do not create Apple Pay or Pass Type certificates unless the team has a disposable Merchant ID or Pass Type ID to use.

## Setup

```sh
plutil -lint "App Store.xcodeproj/project.pbxproj"

xcodebuild -project "App Store.xcodeproj" -scheme "App Store" -sdk macosx \
  -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGN_IDENTITY="" \
  build -skipMacroValidation

xcodebuild test -project "App Store.xcodeproj" -scheme "App Store" \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:"App Store Tests/JSONDecodingTests/testCertificateDetailDecodesContent" \
  -only-testing:"App Store Tests/JSONDecodingTests/testCertificateRelationshipDocumentsDecode" \
  -only-testing:"App Store Tests/ValidationTests/testCertificateCreateRelationshipsForServiceCertificates" \
  -only-testing:"App Store Tests/ValidationTests/testIdentifierCreateBodies"
```

Optional CSR for live create tests:

```sh
openssl req -new -newkey rsa:2048 -nodes \
  -keyout /tmp/shipyard-certificate-flow.key \
  -out /tmp/shipyard-certificate-flow.csr \
  -subj "/CN=Shipyard Certificate Flow"
```

## Core Scenarios

| ID | Scenario | Expected result |
|---|---|---|
| CERT-01 | Open Certificates from the sidebar | Header shows `Certificates`, total pill, search field, create button, and table rows |
| CERT-02 | Search by name, serial, type, or platform | Matching rows stay visible; empty search state says `No Matching Certificates` |
| CERT-03 | Open certificate detail by row tap | `Certificate Details` sheet opens and fetches `GET /v1/certificates/{id}` |
| CERT-04 | Verify certificate detail fields | Sheet shows name, display name, type, platform, serial, expiration, status, activated state, id, and content availability |
| CERT-05 | Open row context menu | Menu contains `Open Details`, `Download`, and `Revoke` |
| CERT-06 | Open Create Certificate | Form opens with certificate type selector, CSR picker, helper copy, and disabled Create button |
| CERT-07 | Submit without CSR | Create remains disabled; no request is sent |
| CERT-08 | Create duplicate signing certificate | Apple duplicate/pending error is shown inline and changing type clears the stale error |
| CERT-09 | Create disposable signing certificate | Success sheet appears; new certificate is prepended; count increments |
| CERT-10 | Revoke disposable certificate | Confirm dialog warns about profile invalidation; success removes row and refetches profiles |
| CERT-11 | Download from row or detail | `GET /v1/certificates/{id}` fetches certificate content before native save panel opens |

## Apple Pay And Pass Type Scenarios

| ID | Scenario | Expected result |
|---|---|---|
| CERT-PAY-01 | Select `Apple Pay` in create form | Merchant ID field appears and Create is disabled until CSR and Merchant ID resource id are present |
| CERT-PAY-02 | Submit Apple Pay with fake Merchant ID id | Apple returns invalid-related-resource wording, not missing `merchantId` |
| CERT-PASS-01 | Select `Pass Type Id` in create form | Pass Type ID field appears and Create is disabled until CSR and Pass Type ID resource id are present |
| CERT-PASS-02 | Switch between Apple Pay and Pass Type Id | Relationship input clears when the required relationship kind changes |

## Identifier Support Scenarios

| ID | Scenario | Expected result |
|---|---|---|
| ID-01 | Open Identifiers sidebar item | Defaults to Merchant IDs list with search and `Create Merchant ID` |
| ID-02 | Create Merchant ID sheet | Requires name and identifier; request body type is `merchantIds` |
| ID-03 | Switch to Pass Type IDs | Search prompt and create button switch to Pass Type IDs |
| ID-04 | Create Pass Type ID sheet | Requires name and identifier; request body type is `passTypeIds` |
| ID-05 | Switch to App Groups | Shows unsupported public API guidance instead of calling a fake endpoint |

## Documentation Updates After Each Run

- Update `docs/CERTIFICATE_FLOW_TEST_REPORT.md` with date, environment, live result, and any state left behind.
- Record the exact Apple error text when exercising negative server validation.
- If a scenario is blocked by account state, mark it as source-audited or not run rather than treating it as pass.
