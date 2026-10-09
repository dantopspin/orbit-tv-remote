# Orbit release security and operations

## Secrets

Orbit must not contain private API keys, signing certificates, provisioning profiles, environment files, or private keys in Git.

CI rejects common secret formats and tracked secret/signing file types. `.gitignore` also excludes local secret and signing material.

The Fire TV Debug adapter contains a fixed public Lightning-protocol header value used by third-party implementations. It is intentionally named as a protocol header constant and is not an Orbit credential. Fire TV remains Debug-only and is compiled out of Release.

If a real credential is ever committed:

1. Revoke or rotate it at the provider immediately.
2. Remove it from current source.
3. Assume Git history and forks retain the old value.
4. Store replacements outside Git.
5. Add a CI rule that would catch the same credential class next time.

## Production diagnostics

Orbit initializes Apple's MetricKit subscriber and unified logging. Recorded events use coarse categories only and do not log TV IP addresses, device IDs, pairing tokens, PINs, or typed remote text.

Users can open Settings → Support and share a privacy-safe diagnostic summary.

## Main branch policy

Recommended GitHub repository rule for `main`:

- Require a pull request before merging.
- Require the `iOS Build` status check.
- Require branches to be up to date before merge if practical.
- Block force pushes.
- Block branch deletion.
- Apply the rule to administrators as well unless emergency access is deliberately retained.

This is a repository-admin setting and is not represented by a file in Git. Verify it directly in GitHub before public launch.

## Public support

Settings → Support provides:
- a direct route to Orbit's issue tracker;
- a privacy-safe diagnostic summary users can share.

Do not ask users to post pairing codes, credentials, private network addresses, or typed remote content in public reports.
