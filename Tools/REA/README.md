# Orbit REA research toolkit

This directory contains **development-only interoperability research tooling** for Orbit.

Nothing under `Tools/REA/` is part of the iOS app target or the App Store binary.

## Purpose

Use REA when documentation or real-device behavior is unclear and we need evidence for a clean Orbit implementation, especially for:

- Samsung Tizen discovery/pairing edge cases
- LG webOS permissions and request behavior
- Google / Android TV interoperability
- experimental Fire TV work
- future VIDAA, Vizio, Philips, or other adapters
- comparing behavior across firmware/app versions

The goal is to understand observable protocol behavior and then implement our **own Swift adapter code** in Orbit.

Do not copy proprietary source, assets, credentials, DRM logic, authentication bypasses, or protected implementation details.

## Local folders

These paths are intentionally ignored by Git:

```
Tools/REA/targets/       # APK, IPA, .app, binaries
Tools/REA/captures/      # HAR, pcap, pcapng, SAZ
Tools/REA/output/        # JSON/evidence/reports
Tools/REA/snapshots/     # REA analysis snapshots
Tools/REA/work/          # investigation notes containing local evidence
```

Never place pairing tokens, PINs, TV IP addresses, account credentials, private captures, or extracted proprietary apps in committed files.

## Quick start

REA requires a supported Node.js version. Run:

```bash
./Tools/REA/setup.sh
```

This launches REA's own interactive setup and lets you choose which coding agent(s) to connect.

Check readiness without analyzing a target:

```bash
./Tools/REA/doctor.sh
```

Create an investigation workspace:

```bash
./Tools/REA/new-investigation.sh samsung-2024-discovery
```

## Android APK inspection

Static Android analysis uses REA + JADX and requires a full JDK plus a compatible JADX headless MCP JAR configured through `REA_JADX_MCP_JAR`.

Inspect a package:

```bash
./Tools/REA/analyze-android.sh Tools/REA/targets/vendor-remote.apk
```

The script writes JSON output to `Tools/REA/output/` and never modifies the APK.

For deeper class/method work, use the REA CLI directly:

```bash
npx -y rea-agents@latest search-android-classes \
  Tools/REA/targets/vendor-remote.apk Remote

npx -y rea-agents@latest inspect-android-class \
  Tools/REA/targets/vendor-remote.apk com.example.RemoteClient
```

## Native binary inspection

Use Hopper, Ghidra, or IDA only when you are licensed/authorized to do so.

```bash
./Tools/REA/analyze-native.sh \
  Tools/REA/targets/SomeBinary \
  ghidra
```

The script stores the REA snapshot under `Tools/REA/snapshots/`.

## Apple bundles

REA can inventory IPA/.app contents and hand native binaries to a configured native-analysis provider. App Store encryption and platform protections can limit what static analysis can establish.

Prefer observable behavior and authorized test artifacts over speculative decompilation.

## Packet captures

REA can inspect saved packet captures, but its full pcap inspection currently has host/tool requirements. On macOS, use REA only where the selected operation is supported; otherwise analyze the capture with trusted local tooling and keep the raw capture under `Tools/REA/captures/`.

A capture is evidence of what happened in that capture, not proof that every TV/firmware behaves the same way.

## Orbit protocol workflow

For every investigation:

1. State the exact compatibility question.
2. Record target app/device/firmware/version.
3. Separate **observed facts** from **inference**.
4. Capture discovery, pairing, auth persistence, commands, reconnect behavior, and errors only when relevant.
5. Avoid collecting unrelated user data.
6. Convert findings into an Orbit-side adapter design.
7. Implement the smallest clean Swift change.
8. Add tests where the behavior can be represented deterministically.
9. Validate on real hardware.
10. Keep research artifacts out of Git.

Use `Tools/REA/templates/PROTOCOL_INVESTIGATION.md` as the working template.

## Shipping boundary

CI verifies that `Tools/REA/` never appears in the Xcode project file. If someone accidentally adds REA tooling to the shipping target, CI fails.

Orbit must never ship:

- REA
- Hopper/Ghidra/IDA/JADX
- extracted target apps
- packet captures
- research credentials
- private protocol evidence
