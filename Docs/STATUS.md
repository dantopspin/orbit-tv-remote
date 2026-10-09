# Build status

Orbit is in release-candidate stabilization. Feature scope for 1.0 is frozen.

## Implemented in code

- SwiftUI iOS 17 native app shell with light-first design and persisted Dark Mode
- Onboarding and direct-to-remote return flow
- Remote controls: D-pad, touchpad, Home/Back, volume/mute, playback, keyboard, apps and inputs when supported
- Device persistence, switching, capped reconnect backoff, network-return recovery and protocol event streams
- Automatic Android TV Bonjour discovery
- SSDP discovery for Samsung/LG plus manual local-IP fallback; physical-iPhone SSDP requires Apple’s multicast networking entitlement
- Samsung Tizen adapter with metadata identity, secure WebSocket control and token persistence
- LG webOS adapter with secure WebSocket control, prompt pairing, pointer socket supervision and client-key persistence
- Google / Android TV Remote Service v2 adapter with persistent client identity, bounded pairing and stable server-key identity
- StoreKit 2 subscriptions for `orbit.weekly` and `orbit.monthly`
- Free plan: one TV with the complete essential remote
- Orbit Pro: multiple TVs, room labels, Custom Remote and favorite apps/inputs
- Free/Pro identity verification so a different TV cannot inherit the Free slot through a reused IP or Bonjour name
- Free users can reopen discovery/manual IP to recover the same saved TV after a DHCP/IP-address change without deleting its metadata or credentials
- Pro data preservation across subscription expiry
- Valid 1024x1024 RGB app icon with CI validation
- Privacy manifest, acknowledgements and in-app legal screens
- In-app Support screen with privacy-safe diagnostic sharing
- MetricKit and unified logging using coarse, non-sensitive error categories
- CI secret/signing-material scan plus hardened `.gitignore`
- Release builds compile Roku and Fire TV adapters out; those platforms remain experimental/debug-only
- Debug build, unit tests and Release simulator build in CI

## Remaining before internal TestFlight

Items requiring repository work:
- Keep CI green on the final stabilization head
- Complete any fixes exposed by real-TV hardware testing, especially D-pad long-press behavior and LG app/input permissions

Items requiring Apple/developer-account setup:
- Request and receive Apple's multicast networking entitlement before promising Samsung/LG SSDP discovery on physical iPhone
- Add the granted multicast capability to the App ID, provisioning profile and target entitlements
- Set the Apple Developer team for signing
- Create `orbit.weekly` and `orbit.monthly` in App Store Connect in one subscription group and ensure the Paid Apps agreement is active
- Configure privacy-policy URL, Terms/EULA metadata and TestFlight beta details
- Enable a GitHub `main` branch rule requiring PRs + the `iOS Build` status check and blocking force pushes

## Hardware validation required

Do not advertise a TV platform as production-supported until it passes the hardware matrix.

Priority matrix:
1. Samsung Tizen — at least two model years
2. LG webOS — at least two webOS versions
3. Google TV / Android TV — at least one Google streamer and one TV-vendor implementation

Validate pairing, relaunch/reconnect, DHCP address changes, background/foreground recovery, rapid navigation, keyboard/apps/inputs where exposed, power behavior and subscription gating.
