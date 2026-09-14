#!/usr/bin/env bash
# Cut a Notch release: bump version, update CHANGELOG, build Release, tag, upload to GitHub.
#
# Usage:
#   ./scripts/release.sh --build-only          # Release .app in dist/, do not tag or publish
#   ./scripts/release.sh 1.1.0                 # full release of that version
#   ./scripts/release.sh --patch               # bump patch (1.0 -> 1.0.1)
#   ./scripts/release.sh --minor               # bump minor (1.0 -> 1.1.0)
#   ./scripts/release.sh --major               # bump major (1.0 -> 2.0.0)
#   ./scripts/release.sh 1.1.0 --no-publish    # version, changelog, build, commit, tag — no GitHub
#   ./scripts/release.sh 1.1.0 --publish-only  # upload existing dist zip + tag to GitHub
#
# Flags: --yes  skip confirmation   --notes "…"  extra notes   --notes-file FILE
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

PROJECT="Notch.xcodeproj"
SCHEME="Notch"
PRODUCT="Notch"
DIST="$ROOT/dist"
DERIVED="$ROOT/.derivedData"
CHANGELOG="$ROOT/CHANGELOG.md"
PBXPROJ="$ROOT/Notch.xcodeproj/project.pbxproj"

VERSION=""
BUMP=""
BUILD_ONLY=0
NO_PUBLISH=0
PUBLISH_ONLY=0
YES=0
NOTES=""
NOTES_FILE=""
DATE="$(date +%F)"

die() { echo "error: $*" >&2; exit 1; }
info() { echo "==> $*"; }

usage() {
  awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --build-only) BUILD_ONLY=1 ;;
    --no-publish) NO_PUBLISH=1 ;;
    --publish-only) PUBLISH_ONLY=1 ;;
    --yes|-y) YES=1 ;;
    --patch) BUMP="patch" ;;
    --minor) BUMP="minor" ;;
    --major) BUMP="major" ;;
    --notes) NOTES="${2:-}"; shift ;;
    --notes-file) NOTES_FILE="${2:-}"; shift ;;
    -*) die "unknown option: $1" ;;
    *)
      [[ -z "$VERSION" ]] || die "unexpected argument: $1"
      VERSION="$1"
      ;;
  esac
  shift
done

current_marketing_version() {
  sed -n 's/.*MARKETING_VERSION = \([^;]*\);/\1/p' "$PBXPROJ" | head -n 1
}

current_build_number() {
  sed -n 's/.*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "$PBXPROJ" | head -n 1
}

parse_version() {
  python3 -c '
import sys
raw = sys.argv[1].strip()
if raw.startswith("v"):
    raw = raw[1:]
core = raw.split("-", 1)[0]
parts = core.split(".")
if not parts or not all(p.isdigit() for p in parts) or not (2 <= len(parts) <= 3):
    raise SystemExit(f"invalid version: {sys.argv[1]}")
while len(parts) < 3:
    parts.append("0")
print(".".join(str(int(p)) for p in parts[:3]), raw)
' "$1"
}

bump_version() {
  python3 -c '
import sys
maj, mino, pat = [int(x) for x in sys.argv[1].split(".")]
kind = sys.argv[2]
if kind == "major":
    maj, mino, pat = maj + 1, 0, 0
elif kind == "minor":
    mino, pat = mino + 1, 0
elif kind == "patch":
    pat += 1
else:
    raise SystemExit("unknown bump")
print(f"{maj}.{mino}.{pat}")
' "$1" "$2"
}

version_gt() {
  python3 -c '
import sys
a = [int(x) for x in sys.argv[1].split(".")]
b = [int(x) for x in sys.argv[2].split(".")]
raise SystemExit(0 if a > b else 1)
' "$1" "$2"
}

normalize_version() {
  local parsed canonical original
  parsed="$(parse_version "$1")"
  canonical="${parsed%% *}"
  original="${parsed#* }"
  # Keep two-component versions as written (1.0), otherwise canonical 1.2.3.
  if [[ "$original" == *.*.* || "$original" == *-* ]]; then
    echo "$original"
  elif [[ "$canonical" == *.0 ]]; then
    echo "${canonical%.0}"
  else
    echo "$canonical"
  fi
}

last_release_tag() {
  git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || true
}

git_log_notes() {
  local from="$1"
  local range
  if [[ -n "$from" ]]; then
    range="${from}..HEAD"
  else
    range="HEAD"
  fi
  git log --no-merges --pretty=format:'- %s' "$range" \
    | grep -Ev '^- (Initial commit|Release v|Bump version|Prepare .* release)' \
    || true
}

unreleased_notes() {
  python3 - "$CHANGELOG" <<'PY'
import pathlib, re, sys
path = pathlib.Path(sys.argv[1])
if not path.exists():
    raise SystemExit(0)
text = path.read_text()
match = re.search(r"## \[Unreleased\][^\n]*\n(.*?)(?=\n## \[|\Z)", text, flags=re.S)
if not match:
    raise SystemExit(0)
body = match.group(1).strip()
if body:
    print(body)
PY
}

apply_changelog() {
  local version="$1"
  local date="$2"
  local notes="$3"
  python3 - "$CHANGELOG" "$version" "$date" "$notes" <<'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
version, date, notes = sys.argv[2], sys.argv[3], sys.argv[4].strip()
if not notes:
    raise SystemExit("changelog notes are empty")

header = """# Changelog

All notable changes to Notch are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

"""
text = path.read_text() if path.exists() else header
if "## [Unreleased]" not in text:
    text = header + text.lstrip()

text, count = re.subn(
    r"## \[Unreleased\][^\n]*\n(.*?)(?=\n## \[|\Z)",
    f"## [Unreleased]\n\n## [{version}] - {date}\n\n{notes}\n\n",
    text,
    count=1,
    flags=re.S,
)
if count != 1:
    raise SystemExit("could not update Unreleased section in CHANGELOG.md")

text = re.sub(r"\n\[Unreleased\]:.*\Z", "\n", text, flags=re.S)
text = text.rstrip() + "\n\n"

headings = re.findall(r"^## \[([^\]]+)\]", text, flags=re.M)
versions = [h for h in headings if h != "Unreleased"]
repo = "https://github.com/djui/Notch"
if versions:
    text += f"[Unreleased]: {repo}/compare/v{versions[0]}...HEAD\n"
else:
    text += f"[Unreleased]: {repo}/commits/main\n"
for i, ver in enumerate(versions):
    text += f"[{ver}]: {repo}/releases/tag/v{ver}\n"

path.write_text(text)
PY
}

set_versions() {
  local marketing="$1"
  local build="$2"
  python3 - "$PBXPROJ" "$marketing" "$build" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
marketing, build = sys.argv[2], sys.argv[3]
text = path.read_text()
text, n1 = __import__("re").subn(
    r"MARKETING_VERSION = [^;]*;",
    f"MARKETING_VERSION = {marketing};",
    text,
)
text, n2 = __import__("re").subn(
    r"CURRENT_PROJECT_VERSION = [^;]*;",
    f"CURRENT_PROJECT_VERSION = {build};",
    text,
)
if n1 < 1 or n2 < 1:
    raise SystemExit("could not update version settings in project.pbxproj")
path.write_text(text)
PY
}

github_repo() {
  local url
  url="$(git remote get-url origin 2>/dev/null || true)"
  [[ -n "$url" ]] || die "no origin remote"
  python3 -c '
import re, sys
url = sys.argv[1].strip()
url = re.sub(r"^git@github.com:", "https://github.com/", url)
url = re.sub(r"^ssh://git@github.com/", "https://github.com/", url)
url = re.sub(r"\.git$", "", url)
m = re.search(r"github.com[:/]([^/]+/[^/]+)$", url)
if not m:
    raise SystemExit("origin is not a GitHub remote")
print(m.group(1))
' "$url"
}

confirm() {
  local prompt="$1"
  if [[ "$YES" == 1 ]]; then
    return 0
  fi
  if [[ ! -t 0 ]]; then
    die "refusing to continue without --yes (stdin is not a terminal)"
  fi
  local reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" == "y" || "$reply" == "Y" ]]
}

require_clean_tree() {
  local dirty
  dirty="$(git status --porcelain | awk '$NF != "CHANGELOG.md"')"
  if [[ -n "$dirty" ]]; then
    die "working tree is not clean; commit or stash first (CHANGELOG.md may still be edited)"
  fi
}

require_main() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"
  [[ "$branch" == "main" ]] || die "release from main (currently on ${branch})"
}

built_app_path() {
  echo "$DERIVED/Build/Products/Release/${PRODUCT}.app"
}

build_release() {
  info "building Release"
  mkdir -p "$DIST"
  xcodebuild \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination "generic/platform=macOS" \
    -quiet \
    ONLY_ACTIVE_ARCH=NO \
    build

  local app
  app="$(built_app_path)"
  [[ -d "$app" ]] || die "Release app missing at ${app}"

  local running
  running="$(pgrep -f "${DIST}/${PRODUCT}.app/Contents/MacOS/${PRODUCT}" || true)"
  if [[ -n "$running" ]]; then
    info "quitting running dist/${PRODUCT}.app"
    osascript -e "tell application \"${PRODUCT}\" to quit" >/dev/null 2>&1 || true
    sleep 1
  fi

  rm -rf "$DIST/${PRODUCT}.app"
  ditto "$app" "$DIST/${PRODUCT}.app"
  xattr -cr "$DIST/${PRODUCT}.app" 2>/dev/null || true

  local short build
  short="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST/${PRODUCT}.app/Contents/Info.plist")"
  build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$DIST/${PRODUCT}.app/Contents/Info.plist")"
  info "built ${PRODUCT}.app ${short} (${build})"

  codesign --verify --deep "$DIST/${PRODUCT}.app"
}

package_zip() {
  local version="$1"
  local zip_path="$DIST/${PRODUCT}-${version}.zip"
  rm -f "$zip_path"
  ditto -c -k --keepParent "$DIST/${PRODUCT}.app" "$zip_path"
  echo "$zip_path"
}

release_notes_body() {
  local version="$1"
  python3 - "$CHANGELOG" "$version" <<'PY'
import pathlib, re, sys
text = pathlib.Path(sys.argv[1]).read_text()
version = sys.argv[2]
match = re.search(
    rf"## \[{re.escape(version)}\][^\n]*\n(.*?)(?=\n## \[|\n\[Unreleased\]:|\Z)",
    text,
    flags=re.S,
)
body = match.group(1).strip() if match else ""
print(body)
PY
}

publish_github() {
  local version="$1"
  local zip_path="$2"
  local notes_body="$3"
  command -v gh >/dev/null || die "gh is not installed (brew install gh)"
  gh auth status -h github.com >/dev/null 2>&1 || die "GitHub CLI is not authenticated; run: gh auth refresh -h github.com"

  local repo tag tmp
  repo="$(github_repo)"
  tag="v${version}"
  tmp="$(mktemp)"
  cat >"$tmp" <<EOF
${notes_body}

## Install

Download \`${PRODUCT}-${version}.zip\`, unzip, and move \`${PRODUCT}.app\` to \`/Applications\`.

This build is signed with an Apple Development certificate. If macOS refuses to open it, run:

    xattr -cr /Applications/${PRODUCT}.app

Then open the app normally.
EOF

  info "pushing ${tag}"
  git push origin HEAD
  git push origin "$tag"

  if gh release view "$tag" --repo "$repo" >/dev/null 2>&1; then
    info "updating GitHub release ${tag}"
    gh release upload "$tag" "$zip_path" --repo "$repo" --clobber
    gh release edit "$tag" --repo "$repo" --title "${PRODUCT} ${version}" --notes-file "$tmp"
  else
    info "creating GitHub release ${tag}"
    gh release create "$tag" "$zip_path" \
      --repo "$repo" \
      --title "${PRODUCT} ${version}" \
      --notes-file "$tmp"
  fi
  rm -f "$tmp"
}

# --- --build-only ----------------------------------------------------------

if [[ "$BUILD_ONLY" == 1 ]]; then
  [[ -z "$VERSION" && -z "$BUMP" && "$PUBLISH_ONLY" == 0 ]] || die "--build-only cannot be combined with a version or publish flags"
  build_release
  echo
  echo "Release app: $DIST/${PRODUCT}.app"
  echo "Run it with:  open \"$DIST/${PRODUCT}.app\""
  exit 0
fi

CURRENT="$(current_marketing_version)"
CURRENT_BUILD="$(current_build_number)"
[[ -n "$CURRENT" && -n "$CURRENT_BUILD" ]] || die "could not read version from project.pbxproj"

if [[ -n "$BUMP" ]]; then
  [[ -z "$VERSION" ]] || die "pass a version or a bump flag, not both"
  PARSED="$(parse_version "$CURRENT")"
  VERSION="$(bump_version "${PARSED%% *}" "$BUMP")"
elif [[ -n "$VERSION" ]]; then
  VERSION="$(normalize_version "$VERSION")"
else
  usage
  echo
  die "pass a version (e.g. 1.1.0) or --patch / --minor / --major"
fi

TAG="v${VERSION}"
ZIP="$DIST/${PRODUCT}-${VERSION}.zip"

if [[ "$PUBLISH_ONLY" == 1 ]]; then
  [[ -f "$ZIP" ]] || die "missing ${ZIP}; build a release first"
  git rev-parse "$TAG" >/dev/null 2>&1 || die "missing git tag ${TAG}"
  NOTES_BODY="$(release_notes_body "$VERSION")"
  [[ -n "$NOTES_BODY" ]] || die "no CHANGELOG section for ${VERSION}"
  publish_github "$VERSION" "$ZIP" "$NOTES_BODY"
  exit 0
fi

require_main
require_clean_tree

if git rev-parse "$TAG" >/dev/null 2>&1; then
  die "tag ${TAG} already exists"
fi

PARSED_CURRENT="$(parse_version "$CURRENT")"
PARSED_NEXT="$(parse_version "$VERSION")"
CURRENT_CANON="${PARSED_CURRENT%% *}"
NEXT_CANON="${PARSED_NEXT%% *}"
if [[ "$NEXT_CANON" != "$CURRENT_CANON" ]]; then
  version_gt "$NEXT_CANON" "$CURRENT_CANON" || die "version ${VERSION} is not greater than current ${CURRENT}"
fi

NEXT_BUILD=$((CURRENT_BUILD + 1))
if [[ "$NEXT_CANON" == "$CURRENT_CANON" && "$CURRENT_BUILD" == "1" && -z "$(last_release_tag)" ]]; then
  NEXT_BUILD="$CURRENT_BUILD"
fi

if [[ -n "$NOTES_FILE" ]]; then
  [[ -f "$NOTES_FILE" ]] || die "notes file not found: ${NOTES_FILE}"
  NOTES="$(cat "$NOTES_FILE")"
fi

CHANGE_NOTES="$(unreleased_notes)"
if [[ -n "$NOTES" ]]; then
  if [[ -n "$CHANGE_NOTES" ]]; then
    CHANGE_NOTES="${NOTES}"$'\n\n'"${CHANGE_NOTES}"
  else
    CHANGE_NOTES="$NOTES"
  fi
fi
if [[ -z "$CHANGE_NOTES" ]]; then
  CHANGE_NOTES="$(git_log_notes "$(last_release_tag)")"
fi
CHANGE_NOTES="$(printf '%s\n' "$CHANGE_NOTES" | sed -e 's/[[:space:]]*$//' | sed -e '/./,$!d')"
[[ -n "$CHANGE_NOTES" ]] || die "no changelog notes; edit CHANGELOG.md [Unreleased] or pass --notes"

echo "Version:  ${CURRENT} (${CURRENT_BUILD}) -> ${VERSION} (${NEXT_BUILD})"
echo "Tag:      ${TAG}"
echo "Date:     ${DATE}"
echo
echo "Changelog:"
echo "$CHANGE_NOTES"
echo

confirm "Create ${TAG} and $([[ "$NO_PUBLISH" == 1 ]] && echo "tag locally" || echo "publish to GitHub")?" || die "aborted"

apply_changelog "$VERSION" "$DATE" "$CHANGE_NOTES"
set_versions "$VERSION" "$NEXT_BUILD"

build_release
BUILT_SHORT="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$DIST/${PRODUCT}.app/Contents/Info.plist")"
[[ "$BUILT_SHORT" == "$VERSION" ]] || die "built app version is ${BUILT_SHORT}, expected ${VERSION}"

ZIP="$(package_zip "$VERSION")"
info "packed $(basename "$ZIP")"

git add CHANGELOG.md Notch.xcodeproj/project.pbxproj Notch/Info.plist
if [[ -z "$(git diff --cached --name-only)" ]]; then
  die "nothing to commit"
fi
git commit -m "$(cat <<EOF
Release ${TAG}.

EOF
)"
git tag -a "$TAG" -m "${PRODUCT} ${VERSION}"

echo
echo "Tagged ${TAG} at $(git rev-parse --short HEAD)"
echo "App:  $DIST/${PRODUCT}.app"
echo "Zip:  $ZIP"
echo "Run:  open \"$DIST/${PRODUCT}.app\""

if [[ "$NO_PUBLISH" == 1 ]]; then
  echo
  echo "Skipped publish. Later: git push origin HEAD ${TAG} && $0 ${VERSION} --publish-only --yes"
  exit 0
fi

NOTES_BODY="$(release_notes_body "$VERSION")"
publish_github "$VERSION" "$ZIP" "$NOTES_BODY"
echo
echo "Published: https://github.com/$(github_repo)/releases/tag/${TAG}"
