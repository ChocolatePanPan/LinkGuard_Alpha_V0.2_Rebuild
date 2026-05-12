#!/usr/bin/env zsh
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
version_file="$repo_root/VERSION"
manifest_file="$repo_root/VERSION.json"
swift_version_file="$repo_root/v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core/Sources/LinkGuardV03Core/Versioning.swift"

usage() {
  printf 'Usage: scripts/version.sh [show|check|tag]\n'
}

read_version() {
  tr -d '[:space:]' < "$version_file"
}

json_field() {
  local field_name="$1"
  sed -nE 's/^[[:space:]]*"'"$field_name"'"[[:space:]]*:[[:space:]]*"?([^",]+)"?,?[[:space:]]*$/\1/p' "$manifest_file" | head -1
}

show_version() {
  local version tag build branch commit dirty
  version=$(read_version)
  tag="v$version"
  build=$(json_field buildNumber)
  branch=$(git rev-parse --abbrev-ref HEAD)
  commit=$(git rev-parse --short HEAD)
  dirty="false"
  if [[ -n "$(git status --porcelain)" ]]; then
    dirty="true"
  fi

  printf 'version=%s\n' "$version"
  printf 'tag=%s\n' "$tag"
  printf 'build=%s\n' "$build"
  printf 'branch=%s\n' "$branch"
  printf 'commit=%s\n' "$commit"
  printf 'dirty=%s\n' "$dirty"
}

check_version() {
  local version manifest_version manifest_tag expected_tag
  version=$(read_version)
  expected_tag="v$version"
  manifest_version=$(json_field version)
  manifest_tag=$(json_field gitTag)

  if [[ "$manifest_version" != "$version" ]]; then
    printf 'VERSION mismatch: VERSION=%s VERSION.json=%s\n' "$version" "$manifest_version" >&2
    exit 1
  fi

  if [[ "$manifest_tag" != "$expected_tag" ]]; then
    printf 'tag mismatch: expected=%s VERSION.json=%s\n' "$expected_tag" "$manifest_tag" >&2
    exit 1
  fi

  if ! grep -q "gitTag: \"$expected_tag\"" "$swift_version_file"; then
    printf 'Swift Versioning.swift does not contain gitTag %s\n' "$expected_tag" >&2
    exit 1
  fi

  if ! grep -q "\"$version\"" "$swift_version_file" && ! grep -q 'major: 0, minor: 3, patch: 0' "$swift_version_file"; then
    printf 'Swift Versioning.swift does not appear to contain version %s\n' "$version" >&2
    exit 1
  fi

  printf 'Version files are consistent: %s\n' "$version"
}

create_tag() {
  local version tag
  version=$(read_version)
  tag="v$version"

  check_version

  if [[ -n "$(git status --porcelain)" ]]; then
    printf 'Working tree is dirty. Commit version changes before tagging.\n' >&2
    exit 1
  fi

  if git rev-parse "$tag" >/dev/null 2>&1; then
    printf 'Tag already exists: %s\n' "$tag"
    exit 0
  fi

  git tag -a "$tag" -m "LinkGuard $version"
  printf 'Created tag %s at %s\n' "$tag" "$(git rev-parse --short HEAD)"
}

command_name="${1:-show}"
case "$command_name" in
  show)
    show_version
    ;;
  check)
    check_version
    ;;
  tag)
    create_tag
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
