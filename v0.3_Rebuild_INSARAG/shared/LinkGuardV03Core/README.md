# LinkGuardV03Core

Shared Swift framework skeleton for LinkGuard v0.3.

## Scope

- app role profiles
- app runtime logic
- ICS and INSARAG identifiers
- permission matrix
- command model
- incident, task, alert, map, medical, finance and AAR models
- sync envelopes
- transport topology
- in-memory transport hub for validation
- offline queue policy
- JSON round-trip helpers

## App logic

Each app gets a `LinkGuardAppRuntime` from its `DeviceIdentity`. The runtime loads the matching role profile and blueprint, then checks `AppLogicGate` before building outbound envelopes.

Implemented runtime coverage:

- `LinkGuard-UCC`
- `LinkGuard-SCC`
- `LinkGuard-SCC-iPad`
- `LinkGuard-TL`
- `LinkGuard-TL-iPad`
- `LinkGuard-TE`
- `LinkGuard-VO`
- `LinkGuard-EMT`
- `LinkGuard-EMT-iPad`

## Transport chain

`TransportTopology` routes each `SyncMessageType` by operational policy:

- command spine: UCC, SCC, SCC iPad, TL, TL iPad
- field operations: UCC, SCC, SCC iPad, TL, TL iPad, TE, VO
- broadcast: all apps
- medical clinical: EMT, EMT iPad only
- medical operational: UCC, SCC, SCC iPad, EMT, EMT iPad
- finance: UCC
- audit: all apps

`InMemoryTransportHub` validates the delivery chain before real networking is attached to the app targets.

## Validation

```bash
swift test
```

Current test coverage includes all app runtime initialization, permission gates, alert broadcast, clinical medical isolation, field task routing, evacuation routing, offline queue priority and sync envelope round-trip.

## Versioning

`LinkGuardVersionInfo.current` exposes the repo release baseline to app targets.

- Version: `0.3.0-alpha.1`
- Git tag: `v0.3.0-alpha.1`
- Build number: `300001`

Repo-level version files live at `VERSION` and `VERSION.json`. Use `scripts/version.sh check` before creating a release tag.

## Rule

Each role-specific app should depend on this package instead of redefining model or protocol types.
