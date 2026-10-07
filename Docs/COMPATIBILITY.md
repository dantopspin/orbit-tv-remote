# Compatibility engineering notes

Orbit isolates TV ecosystems behind protocol adapters and exposes only runtime capabilities that the current device supports.

## Production support policy

A platform is not advertised as supported until:

1. Discovery/manual connection and pairing work on real hardware.
2. Core remote commands are reliable.
3. Credentials and reconnect behavior survive app relaunches.
4. DHCP/address changes do not create duplicate TVs or break the Free slot.
5. Vendor terms and current platform policy permit a third-party iOS remote.
6. The capability set is tested across representative models/firmware.

## Samsung Tizen

Release candidate adapter:
- HTTP `/api/v2/` metadata probe for side-effect-free identity
- secure WebSocket control on port 8002
- token persistence
- pairing revocation handling
- D-pad, text, playback, volume and input commands according to reported capability

Needs hardware validation across model years. Older models that only expose the legacy insecure WebSocket path are not part of the initial production claim.

## LG webOS

Release candidate adapter:
- secure WebSocket registration on port 3001
- generic prompt-based permission manifest
- client-key persistence
- stable device UUID identity
- pointer-input socket with liveness supervision
- apps, inputs, keyboard, playback and navigation endpoints

Orbit does not fall back to plaintext `ws://` for production credentials. Current webOS 26 ecosystem reports also make old signed/test manifests a compatibility risk, so the release candidate uses prompt-approved generic permissions rather than a baked-in LG test signature.

Needs hardware validation on multiple webOS versions.

## Google / Android TV

Release candidate adapter uses the pinned AndroidTVRemoteControl package for Remote Service v2:
- persistent client certificate identity
- bounded pairing and reconnect lifecycle
- stable identity derived from the TV server key
- provisional IP/Bonjour names are never treated as durable TV identity
- background pairing recovery
- D-pad, power, volume, playback and channel/input key codes where the receiver honors them

Needs hardware validation across Google and OEM Android TV implementations.

## Roku

Development-only.

A Roku ECP adapter exists for internal work, but Release builds compile it out. Roku's current ECP documentation/policy for third-party mobile applications remains a release concern. Do not market Roku compatibility until policy and hardware validation are resolved.

## Fire TV

Development-only.

Orbit contains an experimental Fire TV interoperability adapter based on community protocol research. Release builds compile it out. Do not market or ship Fire TV support until protocol stability, hardware behavior and Amazon policy are validated.

## Out of 1.0 scope

VIDAA, Vizio, Philips and Apple TV are not part of the 1.0 release scope.
