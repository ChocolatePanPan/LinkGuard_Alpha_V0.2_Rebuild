#!/usr/bin/env zsh
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
version_file="$repo_root/VERSION"
manifest_file="$repo_root/VERSION.json"
swift_version_file="$repo_root/v0.3_Rebuild_INSARAG/shared/LinkGuardV03Core/Sources/LinkGuardV03Core/Versioning.swift"

usage() {
  printf 'Usage: scripts/version.sh [show|check|bump-alpha|tag|push-check]\n'
}

read_version() {
  tr -d '[:space:]' < "$version_file"
}

json_field() {
  local field_name="$1"
  sed -nE 's/^[[:space:]]*"'"$field_name"'"[[:space:]]*:[[:space:]]*"?([^",]+)"?,?[[:space:]]*$/\1/p' "$manifest_file" | head -1
}

abort() {
  printf '%s\n' "$1" >&2
  exit 1
}

version_major() {
  printf '%s' "$1" | sed -nE 's/^([0-9]+)\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$/\1/p'
}

version_minor() {
  printf '%s' "$1" | sed -nE 's/^[0-9]+\.([0-9]+)\.[0-9]+(-[0-9A-Za-z.-]+)?$/\1/p'
}

version_patch() {
  printf '%s' "$1" | sed -nE 's/^[0-9]+\.[0-9]+\.([0-9]+)(-[0-9A-Za-z.-]+)?$/\1/p'
}

version_prerelease() {
  printf '%s' "$1" | sed -nE 's/^[0-9]+\.[0-9]+\.[0-9]+-([0-9A-Za-z.-]+)$/\1/p'
}

short_version_for() {
  printf '%s' "$1" | sed -nE 's/^([0-9]+\.[0-9]+\.[0-9]+)(-[0-9A-Za-z.-]+)?$/\1/p'
}

release_channel_for() {
  local prerelease
  prerelease=$(version_prerelease "$1")
  if [[ -z "$prerelease" ]]; then
    printf 'stable'
  elif [[ "$prerelease" == alpha.* ]]; then
    printf 'alpha'
  elif [[ "$prerelease" == beta.* ]]; then
    printf 'beta'
  elif [[ "$prerelease" == rc.* ]]; then
    printf 'releaseCandidate'
  else
    abort "Unsupported prerelease channel: $prerelease"
  fi
}

swift_prerelease_literal() {
  local prerelease="$1"
  local -a identifiers
  local output
  if [[ -z "$prerelease" ]]; then
    printf '[]'
    return
  fi

  identifiers=("${(@s:.:)prerelease}")
  output="["
  for identifier in "$identifiers[@]"; do
    if [[ "$output" != "[" ]]; then
      output+=", "
    fi
    output+="\"$identifier\""
  done
  output+="]"
  printf '%s' "$output"
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
  local version manifest_version manifest_short manifest_build manifest_channel manifest_tag expected_tag short_version channel major minor patch prerelease swift_prerelease
  version=$(read_version)
  expected_tag="v$version"
  manifest_version=$(json_field version)
  manifest_short=$(json_field shortVersion)
  manifest_build=$(json_field buildNumber)
  manifest_channel=$(json_field releaseChannel)
  manifest_tag=$(json_field gitTag)
  short_version=$(short_version_for "$version")
  channel=$(release_channel_for "$version")
  major=$(version_major "$version")
  minor=$(version_minor "$version")
  patch=$(version_patch "$version")
  prerelease=$(version_prerelease "$version")
  swift_prerelease=$(swift_prerelease_literal "$prerelease")

  if [[ -z "$major" || -z "$minor" || -z "$patch" || -z "$short_version" ]]; then
    abort "Invalid semantic version: $version"
  fi

  if [[ "$manifest_version" != "$version" ]]; then
    abort "VERSION mismatch: VERSION=$version VERSION.json=$manifest_version"
  fi

  if [[ "$manifest_short" != "$short_version" ]]; then
    abort "shortVersion mismatch: expected=$short_version VERSION.json=$manifest_short"
  fi

  if [[ "$manifest_channel" != "$channel" ]]; then
    abort "releaseChannel mismatch: expected=$channel VERSION.json=$manifest_channel"
  fi

  if [[ "$manifest_tag" != "$expected_tag" ]]; then
    abort "tag mismatch: expected=$expected_tag VERSION.json=$manifest_tag"
  fi

  if ! grep -Fq "version: SemanticVersion(major: $major, minor: $minor, patch: $patch, prereleaseIdentifiers: $swift_prerelease)" "$swift_version_file"; then
    abort "Swift Versioning.swift does not contain SemanticVersion $version"
  fi

  if ! grep -Fq "shortVersion: \"$short_version\"" "$swift_version_file"; then
    abort "Swift Versioning.swift does not contain shortVersion $short_version"
  fi

  if ! grep -Fq "buildNumber: $manifest_build" "$swift_version_file"; then
    abort "Swift Versioning.swift does not contain buildNumber $manifest_build"
  fi

  if ! grep -Fq "releaseChannel: .$manifest_channel" "$swift_version_file"; then
    abort "Swift Versioning.swift does not contain releaseChannel $manifest_channel"
  fi

  if ! grep -Fq "gitTag: \"$expected_tag\"" "$swift_version_file"; then
    abort "Swift Versioning.swift does not contain gitTag $expected_tag"
  fi

  printf 'Version files are consistent: %s\n' "$version"
}

update_version_files() {
  local new_version="$1"
  local new_build="$2"
  local new_notes="$3"
  local new_short new_channel new_tag major minor patch prerelease swift_prerelease
  new_short=$(short_version_for "$new_version")
  new_channel=$(release_channel_for "$new_version")
  new_tag="v$new_version"
  major=$(version_major "$new_version")
  minor=$(version_minor "$new_version")
  patch=$(version_patch "$new_version")
  prerelease=$(version_prerelease "$new_version")
  swift_prerelease=$(swift_prerelease_literal "$prerelease")

  printf '%s\n' "$new_version" > "$version_file"
  perl -0pi -e 's/"version": "[^"]+"/"version": "'"$new_version"'"/' "$manifest_file"
  perl -0pi -e 's/"shortVersion": "[^"]+"/"shortVersion": "'"$new_short"'"/' "$manifest_file"
  perl -0pi -e 's/"buildNumber": [0-9]+/"buildNumber": '"$new_build"'/' "$manifest_file"
  perl -0pi -e 's/"releaseChannel": "[^"]+"/"releaseChannel": "'"$new_channel"'"/' "$manifest_file"
  perl -0pi -e 's/"gitTag": "[^"]+"/"gitTag": "'"$new_tag"'"/' "$manifest_file"
  perl -0pi -e 's/"notes": "[^"]+"/"notes": "'"$new_notes"'"/' "$manifest_file"

  perl -0pi -e 's/version: SemanticVersion\(major: [0-9]+, minor: [0-9]+, patch: [0-9]+, prereleaseIdentifiers: \[[^\]]*\]\)/version: SemanticVersion(major: '"$major"', minor: '"$minor"', patch: '"$patch"', prereleaseIdentifiers: '"$swift_prerelease"')/' "$swift_version_file"
  perl -0pi -e 's/shortVersion: "[^"]+"/shortVersion: "'"$new_short"'"/' "$swift_version_file"
  perl -0pi -e 's/buildNumber: [0-9]+/buildNumber: '"$new_build"'/' "$swift_version_file"
  perl -0pi -e 's/releaseChannel: \.[A-Za-z]+/releaseChannel: .'"$new_channel"'/' "$swift_version_file"
  perl -0pi -e 's/gitTag: "[^"]+"/gitTag: "'"$new_tag"'"/' "$swift_version_file"
  perl -0pi -e 's/notes: "[^"]+"/notes: "'"$new_notes"'"/' "$swift_version_file"
}

bump_alpha() {
  local current major minor patch prerelease current_alpha next_alpha next_version current_build next_build notes
  current=$(read_version)
  major=$(version_major "$current")
  minor=$(version_minor "$current")
  patch=$(version_patch "$current")
  prerelease=$(version_prerelease "$current")
  current_build=$(json_field buildNumber)

  if [[ -z "$major" || -z "$minor" || -z "$patch" || -z "$current_build" ]]; then
    abort "Cannot bump invalid current version: $current"
  fi

  if [[ "$prerelease" == alpha.* ]]; then
    current_alpha="${prerelease#alpha.}"
    if [[ "$current_alpha" != <-> ]]; then
      abort "Cannot bump malformed alpha prerelease: $prerelease"
    fi
    next_alpha=$((current_alpha + 1))
  else
    next_alpha=1
  fi

  next_version="$major.$minor.$patch-alpha.$next_alpha"
  next_build=$((current_build + 1))
  notes="Version bumped after implementation update; show build info in app settings and verify tag at push tail."
  update_version_files "$next_version" "$next_build" "$notes"
  printf 'Bumped version: %s -> %s\n' "$current" "$next_version"
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

push_check() {
  local version tag branch head_tag
  version=$(read_version)
  tag="v$version"
  branch=$(git rev-parse --abbrev-ref HEAD)

  check_version

  if [[ -n "$(git status --porcelain)" ]]; then
    abort "Working tree is dirty. Commit version changes before push."
  fi

  head_tag=$(git describe --tags --exact-match HEAD 2>/dev/null || true)
  if [[ "$head_tag" != "$tag" ]]; then
    abort "HEAD is not tagged with $tag. Run scripts/version.sh tag after committing."
  fi

  printf 'Push sequence:\n'
  printf 'git push origin %s\n' "$branch"
  printf 'git push origin %s\n' "$tag"
}

command_name="${1:-show}"
case "$command_name" in
  show)
    show_version
    ;;
  check)
    check_version
    ;;
  bump-alpha)
    bump_alpha
    ;;
  tag)
    create_tag
    ;;
  push-check)
    push_check
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
