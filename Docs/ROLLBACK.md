# Orbit release rollback plan

Orbit is a native iOS app with local-first state and no Orbit backend. A shipped App Store binary cannot be remotely rolled back to an older binary, so recovery means stopping rollout and shipping a corrected build quickly.

## Before every public release

1. Record the exact release commit SHA.
2. Create a release tag for the submitted build.
3. Confirm CI passes Debug build, unit tests, secret scan, app-icon validation, and Release build.
4. Keep the previous known-good release tag and TestFlight build available.
5. Confirm App Store Connect subscription metadata and agreements are unchanged unless the release intentionally modifies them.

## If a launch issue is discovered

### Severity A — crash, purchase breakage, or unsafe destructive behavior

1. Stop or pause phased release in App Store Connect if phased release is enabled.
2. If necessary, temporarily remove the affected version from sale while a replacement is prepared.
3. Branch from the last known-good release tag or revert only the offending commit(s).
4. Do not rewrite `main` history.
5. Increment `CURRENT_PROJECT_VERSION`.
6. Run the complete iOS CI workflow.
7. Archive the clean release commit and upload the replacement build.
8. Request expedited App Review when the defect materially blocks users.
9. Verify purchase, restore, launch, pairing, and the repaired flow in TestFlight before release.

### Severity B — non-blocking regression

1. Keep the current build live if users can safely continue.
2. Create a narrow hotfix branch from `main`.
3. Add a regression test where practical.
4. Run CI and TestFlight validation.
5. Submit the next build normally.

## Data recovery

Orbit has no server database. Saved TVs, preferences, room labels, and favorites are local app data. Pairing credentials are stored in the iOS Keychain.

Avoid changing or deleting local storage keys in a hotfix unless the bug specifically requires a migration. Any migration must preserve existing user data and be tested against data written by the previous public build.

## StoreKit

Orbit Pro entitlement is verified from StoreKit. Do not replace StoreKit entitlement checks with a local emergency flag in Release builds.

If App Store subscription metadata is misconfigured, fix the product or agreement in App Store Connect rather than changing client entitlement logic unless the client is actually defective.

## Release recovery checklist

- [ ] Exact bad build and commit identified
- [ ] Rollout paused if needed
- [ ] Last known-good tag identified
- [ ] Hotfix/revert is minimal
- [ ] Build number incremented
- [ ] Secret scan passes
- [ ] Debug build passes
- [ ] Unit tests pass
- [ ] Release build passes
- [ ] TestFlight smoke test passes
- [ ] Purchase and restore tested
- [ ] Relevant TV hardware retested
- [ ] Replacement submitted
- [ ] Incident notes recorded
