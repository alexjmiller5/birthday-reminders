# Browser Enrollment

**Goal:** Enter a Life Data URL, approve Birthdays through a browser
link, and keep the app's own narrowly scoped credential in device-only Keychain.
No manual token entry or provider/operator credentials.

**Contract:** Reuse Life Data's supported enrollment seam. Generate 24 secure
random bytes as an `lt_` candidate; put only its SHA-256 fingerprint/code in a
canonical approval link. Poll GET `/v1/session` every five seconds with a
monotonic 300-second deadline and 64 KiB response bound. Require exact
`device:<fingerprint>` identity and the service's canonical narrow profile
receipt. Self-revocation is POST `/v1/session`, confirmed only by
`{logged_out:true}`. A 401 is not revocation proof.

Life UI's replica eligibility and legacy full-scope `/login` approval are not
Birthdays authority. Core owns the profile-bound approval
path, canonical session validator and enforced People projection. The phone
needs only id/name/birthday/notify_birthday/deleted_at; the server Tasks writer
is a separate caller. Core has confirmed its deployed profile configuration. The app uses the exact
public birthday reader profile through the reviewed JSC policy; fixtures use
injected synthetic contracts. Real owner approval remains outstanding.

- [x] Inspect Life UI native enrollment and the service's canonical operations.
- [x] Reproduce existing accepted-credential loss on a failed cache write.
- [x] Test/implement CSPRNG/hash, endpoint and approval-origin validation,
  bounded transport, cancellation/replacement/expiry fencing, failed install
  cleanup and accepted-connection preservation.
- [x] Replace manual credential entry with URL and browser-approval controls;
  use the service-configured birthday reader profile and fail closed otherwise.
- [ ] Verify core and native/UI tests, mutation checks, independent review and CI.
- [ ] Bind the published canonical narrow profile; verify real approval and read.
- [ ] Sign/install the verified release and finish owner notification acceptance.

The installer must check that its attempt is current immediately before the
synchronous persistence commit. Persist cache first and use successful Keychain
save as the accepted-connection commit point. Failure or cancellation must leave
the accepted connection intact. A successful commit must not be revoked merely
because the deadline elapsed immediately afterward.

Notification testing is independent of enrollment: Settings can schedule its
test notification without a Life Data connection or any selected birthdays.
