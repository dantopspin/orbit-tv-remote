# Compatibility engineering notes

Orbit targets major Wi-Fi controllable TV platforms through isolated protocol adapters.

## Production support policy

A platform is not advertised as supported until:

1. Discovery and pairing work on real hardware.
2. Core remote commands are reliable.
3. Credentials and reconnect behavior survive app relaunches.
4. Vendor terms and current platform policy permit a third-party iOS remote.
5. The capability set is tested across representative models.

## Roku

A development ECP adapter exists in the current foundation. It uses local device-info, keypress/keydown/keyup, app listing and input commands.

Important release note: Roku's current ECP documentation contains a statement that ECP commands may not be sent from third-party platforms such as mobile applications, while the same documentation also contains older examples that reference iPhone/iPad clients. Because those statements conflict, Orbit must treat Roku ECP as development-only until the current third-party mobile-use policy is clarified.

Do not market Roku compatibility or ship the Roku adapter as a production claim until this is resolved.

## Next platforms

Engineering priority after the shared control lifecycle is stable:

1. Samsung Tizen
2. LG webOS
3. Google / Android TV
4. Fire TV
5. VIDAA
6. Vizio
7. Philips variants

Each adapter must report runtime capabilities so Orbit can keep the main remote clean and hide unsupported controls.
