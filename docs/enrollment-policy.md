# Canonical enrollment policy

The bundled `ios/Core/Resources/life-enrollment.js` is the minimal IIFE supplied
by Life Core, with no local policy edits. It exports the public enrollment
functions only. `CoreEnrollmentPolicy` loads it into JavaScriptCore and passes
JSON across the realm boundary. Production uses the configured `birthdays-reader-v1` profile with
exact read grants for People id/name/birthday/notify_birthday/deleted_at.
Synthetic tests inject their own expected profile. Core confirmed deployment
37540666572 and configured secret deployment
`d773cac9-e3b9-48a6-8bfd-11876a298ce2`; the initial profile revision is
`153e267c84de4290d64eb24f5056159d3166dd6e3de20a0dc2f66b29e310bb7e`.
The canonical validator checks exact grants and a valid revision; accepted
receipts retain the actual revision in device-only Keychain.

Provenance:

- Source: https://github.com/alexjmiller5/life-data/pull/19
- Commit: `c5d8f9db9e8a10efed72e370ea7dba312ddbbf9d`
- Public entry: `life-core/enrollment`, `core/src/enrollment.ts`
- Contract: `b95ac80a2b30289866dea79a408135b6339c5975bd9a6bf13060ee9534bc9ecc`
- IIFE SHA-256: `2ce7fb21f13d4bd46031039af6cfa0379ca60f2083dbb136174d7add54cfe8a3`
- Size: 5574 bytes, including source/contract banner; no source map or host path.

Core built this with Bun browser target, IIFE format, minification, and this entry:

```ts
import {ENROLLMENT_POLICY,enrollmentApproval,validateDeviceSession,enrollmentPollResult,sessionRevocationResult} from 'life-core/enrollment';
Object.assign(globalThis,{LifeEnrollment:{ENROLLMENT_POLICY,enrollmentApproval,validateDeviceSession,enrollmentPollResult,sessionRevocationResult}});
```

For an update, obtain Core's reviewed source/artifact and conformance evidence,
replace the resource, update its pinned SHA-256 in the Swift loader and this
receipt, then run the complete native checks. No packages, replica handlers,
service credentials, SQL, HTTP, clock or crypto host bindings are installed in
this JavaScript realm. The native host owns secure randomness, transport,
deadlines and Keychain; Core owns profile authorization rules.
