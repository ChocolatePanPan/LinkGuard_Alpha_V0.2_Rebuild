# Development Workflow

## Version Rule

Every implementation update must update the version before the work is complete.

For the current v0.3 alpha line, use:

```bash
scripts/version.sh bump-alpha
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

The final command in the push sequence must push the matching version tag, for example:

```bash
git push origin main
git push origin v0.3.0-alpha.2
```

Do not push commits or tags unless explicitly requested.

## App Settings

App settings must expose build-time version data from `LinkGuardAppSettingsInfo`. This keeps the visible app version aligned with `VERSION`, `VERSION.json`, `LinkGuardVersionInfo.current`, and the Git tag.