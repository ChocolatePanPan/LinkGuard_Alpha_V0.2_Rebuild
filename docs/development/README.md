# Development Workflow

## Version Rule

Every implementation update must update the version before the work is complete.

GitHub enforces this for product changes on `main` and `release/v0.3`.
If product code, shared models, app targets, resources, or scripts change,
the same push or PR must also update the version files.

For normal alpha implementation bumps, use:

```bash
scripts/version.sh bump-alpha
scripts/version.sh check
```

For named field builds, set the requested version explicitly:

```bash
scripts/version.sh set <version>
scripts/version.sh check
```

After the commit is clean, create the local annotated tag:

```bash
scripts/version.sh tag
```

Before pushing, verify the push tail:

```bash
scripts/version.sh push-check
```

For local preflight before opening a PR, compare against the target branch:

```bash
scripts/require-version-update.sh origin/main HEAD
```

The final command in the push sequence must push the matching version tag, for example:

```bash
git push origin main
git push origin v<version>
```

Do not push commits or tags unless explicitly requested.

## Field Operational Principles

After the firefighter interview, the first priority is not AI. The field gates are reliability, crash resistance, offline operation, three-second actions, glove-safe large controls, night contrast, one-hand operation, low false touches, and short command flows.

See [FIELD_OPERATIONAL_PRINCIPLES.md](FIELD_OPERATIONAL_PRINCIPLES.md).

## App Settings

App settings must expose build-time version data from `LinkGuardAppSettingsInfo`. This keeps the visible app version aligned with `VERSION`, `VERSION.json`, `LinkGuardVersionInfo.current`, and the Git tag.
