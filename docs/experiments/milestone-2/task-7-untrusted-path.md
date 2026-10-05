# Task 7: Untrusted path — **needs the user**

The code's assumed lockdown codes (`-17/-18/-19/-21`) stay unconfirmed until a real untrusted
phone reports one.

- [ ] **Step 1 (user): make this Mac unknown to the phone.** Either use a phone that has never
  paired with this Mac, or reset this one: on the phone, Settings → General → Reset → *Reset
  Location & Privacy* (label from memory for iOS 6 — **[assumed]**), and on the Mac remove the
  stored pairing record: `sudo rm /var/db/lockdown/<UDID>.plist` (the UDID is the
  `UniqueDeviceID:` line of `Tools/bin/ideviceinfo`). This deletes a system pairing record — it is
  yours to run, not the session's.
- [ ] **Step 2: Capture.** Unplug, replug, then run `Tools/bin/ideviceinfo; echo "exit=$?"` and
  paste stderr/exit code into the session. Then launch the app and note the status text.
- [ ] **Step 3: Record the outcome either way.**
  - If a code in the assumed set appears → mark it **verified** in `domain.md` and `research.md`,
    and make the unit-test fixture match the captured stderr byte-for-byte.
  - If another code appears → add it to `untrustedLockdownCodes` and fix the fixture.
  - If the phone **pairs silently with no prompt** → that is the answer: **[assumed, from memory]**
    the "Trust This Computer" dialog arrived in iOS 7, so an iOS 6.1.6 3GS may never present an
    untrusted state. Record it in `domain.md`; keep the trust-code branch (other devices) but
    mark it untestable on this hardware.

Back to the [milestone 2 plan](README.md).
