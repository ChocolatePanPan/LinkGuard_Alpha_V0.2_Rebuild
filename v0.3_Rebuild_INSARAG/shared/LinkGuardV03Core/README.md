# LinkGuardV03Core

Shared Swift framework skeleton for LinkGuard v0.3.

## Scope

- app role profiles
- ICS and INSARAG identifiers
- permission matrix
- incident, task, alert, map, medical, finance and AAR models
- sync envelopes
- offline queue policy
- JSON round-trip helpers

## Rule

Each role-specific app should depend on this package instead of redefining model or protocol types.
