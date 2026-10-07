# Orbit: TV Remote

Native iOS TV remote built in SwiftUI for iOS 17+.

## Product direction

- Light mode by default, optional Dark Mode in Settings.
- Local-network control; no Orbit account required.
- Full essential remote stays useful on Free.
- Premium is convenience: multiple TVs/rooms, custom remote and favorite apps/inputs.
- Planned StoreKit products: `orbit.weekly` and `orbit.monthly`.
- Red is reserved for the power control.

## Current foundation

- Onboarding tutorial
- Light/dark visual system
- Remote UI with D-pad and touchpad modes
- Keyboard sheet
- Apps & Inputs sheet
- Devices and Settings
- StoreKit 2 subscription manager
- Privacy and Terms screens
- TV adapter abstraction
- Roku ECP adapter with manual IP connection for development
- Keychain utility for future TV pairing credentials

## Build

Open `Orbit.xcodeproj` in Xcode 16+ and run the `Orbit` scheme on iOS 17+.

Automatic multi-platform TV discovery and the remaining protocol adapters are the next implementation phase. See `Docs/ARCHITECTURE.md` and `Docs/MULTICAST.md`.
