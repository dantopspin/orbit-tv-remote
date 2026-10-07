# Orbit architecture

Orbit is intentionally split into three layers:

1. **SwiftUI product UI** — onboarding, remote, device management, settings and StoreKit.
2. **Capability model** — the UI asks for remote capabilities instead of knowing manufacturer-specific protocols.
3. **Protocol adapters** — one adapter per TV platform.

`TVControlling` is the boundary between the product UI and vendor protocols. `TVAdapterFactory` chooses the implementation for a saved TV.

## Compatibility roadmap

Initial adapter included in this foundation: Roku ECP (manual local-IP connection for development).

Planned adapters: Samsung Tizen, LG webOS, Google/Android TV, Fire TV, VIDAA, Vizio and Philips variants.

Automatic discovery will live behind `DiscoveryService` so adding protocols does not change onboarding or the remote UI.

## Local-only control

Remote commands are sent over the local network. Pairing credentials required by TV vendors should be stored with `KeychainStore`, never in plain UserDefaults.
