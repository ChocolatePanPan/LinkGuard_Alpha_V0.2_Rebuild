# Versioning

LinkGuard uses a repo-level version manifest and Git tag as the release source of truth.

## Current version

- Version: `0.3.0-alpha.1`
- Git tag: `v0.3.0-alpha.1`
- Build number: `300001`
- Channel: `alpha`
- Series: `v0.3_Rebuild_INSARAG`

## Files

- `VERSION`: plain text version for scripts.
- `VERSION.json`: structured release manifest.
- `scripts/version.sh`: Git-aware version helper.
- `v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core/Sources/LinkGuardV03Core/Versioning.swift`: app-readable version API.

## Git policy

Every released version should have:

1. A commit that updates `VERSION`, `VERSION.json` and `Versioning.swift`.
2. An annotated Git tag named `v<version>` on that commit.
3. No generated build artifacts in the commit.

## Commands

```bash
scripts/version.sh show
scripts/version.sh check
scripts/version.sh tag
```

`tag` creates the annotated tag locally. Push is intentionally separate.
