# Orbit: TV Remote

Native iOS TV remote built in SwiftUI for iOS 17+.

## Product direction

- Light mode by default, optional Dark Mode in Settings.
- Local-network control; no Orbit account required.
- The complete essential remote stays useful on Free.
- Orbit Pro adds multiple TVs/rooms, Custom Remote, and favorite apps/inputs.
- StoreKit products: `orbit.weekly` and `orbit.monthly`.
- Red is reserved for the power control.

## Orbit 1.0 scope

Production-supported platform targets:

- Samsung Tizen
- LG webOS
- Google TV / Android TV

Roku and Fire TV adapters are experimental and compile only in Debug builds.

## Implemented

- Onboarding tutorial and light/dark visual system
- D-pad and touchpad remote modes
- Keyboard, playback, volume, apps and inputs where the TV exposes them
- Device persistence, rooms, switching and Free/Pro identity gating
- Samsung Tizen secure WebSocket adapter with durable identity and token persistence
- LG webOS secure WebSocket adapter with prompt pairing and client-key persistence
- Google / Android TV Remote Service v2 with PIN pairing and durable server-key identity
- Android TV Bonjour discovery
- Samsung/LG SSDP discovery plus manual local-IP connection
- Reconnect supervision with capped backoff and recovery after network return
- StoreKit 2 weekly/monthly subscriptions
- Keychain-backed pairing credentials
- Privacy manifest, legal screens and acknowledgements
- Debug build, unit tests, app-icon validation and Release build in CI

## Discovery on physical iPhone

Samsung/LG automatic SSDP discovery requires Apple’s multicast networking entitlement on physical iPhone. Until that entitlement is granted and provisioned, users can connect those TVs by local IP. Android TV Bonjour discovery does not use the SSDP entitlement.

If a saved TV receives a new DHCP address, Free users can open **Add or Find TV** and reconnect the same physical TV. Orbit verifies durable TV identity before updating the saved endpoint, so the one-TV Free rule is preserved.

## Build

Open `Orbit.xcodeproj` in Xcode 16+ and run the `Orbit` scheme on iOS 17+.

See `Docs/ARCHITECTURE.md`, `Docs/COMPATIBILITY.md`, `Docs/MULTICAST.md`, and `Docs/STATUS.md` for release details.
