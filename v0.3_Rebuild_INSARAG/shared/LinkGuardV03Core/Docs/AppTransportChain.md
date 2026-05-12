# App Transport Chain

This document mirrors the current `TransportTopology` implementation.

## Apps

- `LinkGuard-UCC`
- `LinkGuard-SCC`
- `LinkGuard-SCC-iPad`
- `LinkGuard-TL`
- `LinkGuard-TL-iPad`
- `LinkGuard-TE`
- `LinkGuard-VO`
- `LinkGuard-EMT`
- `LinkGuard-EMT-iPad`

## Route families

| Family | Message types | Recipients |
| --- | --- | --- |
| Command spine | incident, sector, role, command, decision | UCC, SCC, SCC iPad, TL, TL iPad |
| Field operations | worksite, task, map feature | UCC, SCC, SCC iPad, TL, TL iPad, TE, VO |
| Broadcast | alert, alert acknowledgement | all apps |
| Medical clinical | patient update | EMT, EMT iPad |
| Medical operational | evacuation, hospital capacity | UCC, SCC, SCC iPad, EMT, EMT iPad |
| Finance | purchase request, personnel hours | UCC |
| Audit | audit event append | all apps |

## Runtime chain

1. App builds payload through `LinkGuardAppRuntime`.
2. `AppLogicGate` checks required permission.
3. Runtime builds `SyncEnvelope` with idempotency key.
4. Envelope enters `OfflineQueue`.
5. `InMemoryTransportHub` validates current topology.
6. Recipient runtimes apply the envelope into `OperationSnapshot`.
7. Delivered outbound messages are removed from local queue.

Real network adapters should keep the same envelope and replace only the transport layer.