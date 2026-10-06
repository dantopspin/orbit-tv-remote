# Local network discovery and multicast

Orbit has an SSDP scanner for Samsung/LG discovery and a Bonjour scanner for Google / Android TV.

Apple requires the multicast networking entitlement on physical iPhone/iPad hardware for apps that directly send or receive multicast/broadcast packets. Orbit intentionally does **not** commit that entitlement yet because device signing can fail until the Apple developer team has been granted the capability.

## Production checklist

1. Request Apple's `com.apple.developer.networking.multicast` entitlement for the Orbit App ID.
2. After Apple grants it, enable the capability for the App ID and regenerate the provisioning profile.
3. Add an Orbit entitlements file to the target and set `CODE_SIGN_ENTITLEMENTS`.
4. Test SSDP on a signed physical iPhone against Samsung and LG hardware.
5. Keep manual local-IP connection as a fallback for guest, mesh and multicast-isolated networks.

Until the entitlement is granted, Android TV Bonjour discovery can still work on device, while Samsung/LG users may need manual IP connection.
