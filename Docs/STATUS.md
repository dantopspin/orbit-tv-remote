# Build status

This branch is the first native Orbit foundation, not an App Store release candidate.

## Implemented in code

- SwiftUI iOS 17 app shell and Xcode project
- Light-first visual system and manual Dark Mode toggle
- Onboarding tutorial
- Remote UI: D-pad, touchpad, volume, playback, Home/Back, keyboard, apps/inputs
- Device persistence and switching
- StoreKit 2 product/entitlement manager for `orbit.weekly` and `orbit.monthly`
- Free one-TV limit and Premium routing
- Legal/settings screens
- TV protocol abstraction
- Roku ECP control adapter and manual-IP probe
- Keychain storage utility for future pairing tokens

## Next before release

- Automatic discovery (requires protocol scanners; SSDP multicast on physical iPhone also requires Apple's multicast entitlement)
- Samsung Tizen adapter
- LG webOS adapter
- Google/Android TV adapter
- Fire TV, VIDAA, Vizio and Philips adapters
- Vendor-specific pairing UI/credential flow
- Wake-on-LAN where supported
- Premium custom remote editor and favorite persistence
- Accessibility pass, real-device QA and StoreKit configuration
- Final legal controller/contact values and App Store metadata
