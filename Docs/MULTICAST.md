# Local network discovery and multicast

Several television ecosystems use SSDP or other multicast discovery. Apple requires the multicast networking entitlement on physical iPhone/iPad hardware for apps that directly send or receive multicast/broadcast packets.

Orbit does **not** enable that entitlement in the initial project because signing will fail until the Apple developer team has been granted the capability.

Before automatic SSDP discovery is enabled for production:

1. Request Apple's `com.apple.developer.networking.multicast` entitlement for the App ID.
2. Add the entitlement to the target/provisioning profile.
3. Implement protocol-specific scanners behind `DiscoveryService`.
4. Keep the manual local-IP fallback for difficult guest/mesh networks.
