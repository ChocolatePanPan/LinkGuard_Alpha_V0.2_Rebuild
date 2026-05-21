#!/usr/bin/env bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cd "$repo_root"

base_ref="${1:-${BASE_REF:-origin/main}}"
head_ref="${2:-${HEAD_REF:-HEAD}}"

if ! git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
  echo "Cannot resolve base ref: $base_ref" >&2
  exit 1
fi

if ! git rev-parse --verify "$head_ref" >/dev/null 2>&1; then
  echo "Cannot resolve head ref: $head_ref" >&2
  exit 1
fi

changed_files=()
while IFS= read -r path; do
  changed_files+=("$path")
done < <(git diff --name-only "$base_ref" "$head_ref" --)

if [[ "${#changed_files[@]}" -eq 0 ]]; then
  echo "No changed files; version policy skipped."
  exit 0
fi

is_product_file() {
  local path="$1"
  case "$path" in
    VERSION|VERSION.json)
      return 1
      ;;
    v0.3_Rebuild_INSARAG/apps/*|\
    v0.3_Rebuild_INSARAG/shared/*|\
    v0.3_Rebuild_INSARAG/modules/*|\
    v0.3_Rebuild_INSARAG/resources/*|\
    linkguardMB/*|\
    V0.2/*|\
    scripts/*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

version_file_changed=false
product_file_changed=false

for path in "${changed_files[@]}"; do
  case "$path" in
    VERSION|\
    VERSION.json|\
    v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core/Sources/LinkGuardV03Core/Versioning.swift|\
    v0.3_Rebuild_INSARAG/apps/*/*.xcodeproj/project.pbxproj|\
    v0.3_Rebuild_INSARAG/apps/*/*/*.xcodeproj/project.pbxproj)
      version_file_changed=true
      ;;
  esac

  if is_product_file "$path"; then
    product_file_changed=true
  fi
done

if [[ "$product_file_changed" != true ]]; then
  echo "No product files changed; version policy skipped."
  exit 0
fi

if [[ "$version_file_changed" != true ]]; then
  cat >&2 <<'EOF'
Product files changed, but no version files changed.

Before pushing product work, update the version explicitly:
  scripts/version.sh bump-alpha

For a named field build, set the requested version:
  scripts/version.sh set <version>

Then run:
  scripts/version.sh check
EOF
  exit 1
fi

scripts/version.sh check
