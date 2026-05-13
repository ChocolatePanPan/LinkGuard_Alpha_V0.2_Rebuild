# Versioning

LinkGuard uses a repo-level version manifest and Git tag as the release source of truth.

## Current version

- Version: `0.3.1-5`
- Git tag: `v0.3.1-5`
- Build number: `301005`
- Channel: `field`
- Series: `v0.3_Rebuild_INSARAG`

## Files

- `VERSION`: plain text version for scripts.
- `VERSION.json`: structured release manifest.
- `scripts/version.sh`: Git-aware version helper.
- `v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core/Sources/LinkGuardV03Core/Versioning.swift`: app-readable version API.

## Git policy

Every implementation update must bump the version before the update is considered complete. Every released version should have:

1. A commit that updates `VERSION`, `VERSION.json` and `Versioning.swift`.
2. An annotated Git tag named `v<version>` on that commit.
3. No generated build artifacts in the commit.
4. The push sequence must end by pushing the matching tag.

The normal alpha flow after code changes is:

1. Run `scripts/version.sh bump-alpha`.
2. Run tests and `scripts/version.sh check`.
3. Commit the implementation and version bump together.
4. Run `scripts/version.sh tag`.
5. Before pushing, run `scripts/version.sh push-check` and use the printed push sequence. The final push command is always `git push origin v<version>`.

Named field builds use explicit version setting:

1. Run `scripts/version.sh set 0.3.1-5`.
2. Run tests and `scripts/version.sh check`.
3. Commit the implementation and version update together.
4. Run `scripts/version.sh tag`.
5. Before pushing, run `scripts/version.sh push-check` and use the printed push sequence.

App settings must display the build-time version using `LinkGuardAppSettingsInfo`, which is backed by `LinkGuardVersionInfo.current`.

## Commands

```bash
scripts/version.sh show
scripts/version.sh check
scripts/version.sh bump-alpha
scripts/version.sh set 0.3.1-5
scripts/version.sh tag
scripts/version.sh push-check
```

`tag` creates the annotated tag locally. Push is intentionally separate.
