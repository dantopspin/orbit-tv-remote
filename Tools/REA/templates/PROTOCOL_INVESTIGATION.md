# {{INVESTIGATION_NAME}}

## Scope

**Compatibility question**

What exact behavior are we trying to explain or reproduce?

**Authorized target(s)**

- app/package:
- version/build:
- TV/streamer:
- firmware/OS:
- network setup:

**Orbit baseline**

- Orbit commit:
- Orbit build:
- current behavior:
- expected behavior:

## Evidence ledger

Keep facts and interpretation separate.

| ID | Evidence | Source | Observation | Confidence |
| --- | --- | --- | --- | --- |
| E1 |  |  |  |  |

## Discovery

Record only what is needed.

- protocol:
- multicast/broadcast address:
- ports:
- request shape:
- response shape:
- durable identity:
- timing/retry behavior:
- unknowns:

## Pairing

- initiation:
- user-visible confirmation/PIN:
- request sequence:
- timeout:
- rejection behavior:
- re-pair trigger:
- unknowns:

## Authentication / credential persistence

Do **not** paste real credentials here.

- credential type:
- where the target appears to persist it:
- invalidation behavior:
- device-bound or network-bound:
- unknowns:

## Control channel

- transport:
- secure/insecure:
- port:
- connection lifecycle:
- command envelope:
- long-press behavior:
- acknowledgement/error behavior:
- unknowns:

## Capability notes

- navigation:
- volume/mute:
- power/wake:
- keyboard:
- apps:
- inputs:
- playback:
- channels:
- unsupported/unknown:

## Reconnect / lifecycle

- app foreground:
- app background:
- TV sleep/wake:
- DHCP/IP change:
- Wi-Fi interruption:
- token/client-key revocation:
- observed retry/backoff:
- unknowns:

## Error behavior

Record sanitized categories, not private payloads.

- unreachable:
- permission denied:
- malformed response:
- unsupported:
- rate/throttle behavior:
- firmware-specific errors:

## Orbit implementation decision

**What we will implement**

- adapter/discovery change:
- model/state change:
- UI change, if any:
- migration/persistence change:

**What we will not implement**

- speculative behavior:
- vendor-specific private data:
- unsupported shortcuts:

## Tests

- deterministic unit test:
- simulator/integration test:
- physical hardware matrix:
- regression cases:

## Exit criteria

- [ ] evidence is sufficient for the claimed behavior
- [ ] clean Swift implementation written independently
- [ ] no proprietary source/assets copied
- [ ] no credentials/captures committed
- [ ] CI passes
- [ ] real hardware validates the change
