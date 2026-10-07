# Canonical enrollment policy

The bundled `ios/Core/Resources/life-enrollment.js` is the minimal IIFE supplied
by Life Core, with no local policy edits. It exports the public enrollment
functions only. `CoreEnrollmentPolicy` loads it into JavaScriptCore and passes
JSON across the realm boundary. New connections expect `birthdays-editor-v1`:
People id/name/birthday/notify_birthday/deleted_at/updated_at/hub_at reads and
only `tables:patch:people:notify_birthday`. Service deploy `37615482143` shipped
main `7fea375f4ce482623fd13c4a4ef408115d5ea57b`. Configuration deployment
`5a56ea49-84ea-4cc8-9e9d-c07d93cb3642` has profile revision
`811fa070c5409e04f27f00b3d8a74b3778d4efd351cafb9dfdba8a20c6e7ede9`.
Existing reader credentials remain read-only.
Synthetic tests inject their own expected profile. The phone requires the
conditional-patch capability and validates the live session before each edit.
The canonical validator checks exact grants and a valid revision; accepted
receipts retain the actual revision in device-only Keychain.

Provenance:

- Source: https://github.com/alexjmiller5/life-data/pull/23
- Commit: `88bbd6210782c1ccef15e0b7805225f0a6398398`
- Public entry: `life-core/enrollment`, `core/src/enrollment.ts`
- Contract: `40ce1fb59bfe27a26bc878b193d694414c3b491fdc365cb421a96000b6b1c3a0`
- IIFE SHA-256: `cd6a495dd3489a4161a7f7d3d8ce414cb77cc426636bac58181aace67cddcc2f`
- Size: 5744 bytes, including source/contract banner; no source map or host path.

Built from the reviewed Core source with Bun browser target, IIFE format,
minification, and this entry (resolved to the pinned source):

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
