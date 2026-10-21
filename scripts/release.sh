#!/usr/bin/env bash
# Publishes the version recorded in bundle-app.sh as a GitHub release: builds a release app signed with the stable local identity, zips it, pushes the matching vX.Y.Z tag, and attaches the zip.
# The tag must already point at HEAD, and HEAD must be on origin/main; --dry-run stops after the zip so it can be tried before anything is published.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DRY_RUN=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY_RUN=1 ;;
  *)
    echo "Usage: bash scripts/release.sh [--dry-run]" >&2
    exit 2
    ;;
esac

fail() {
  echo "$1" >&2
  exit 1
}

cd "$ROOT"
VERSION="$(sed -n '/CFBundleShortVersionString/{n;s/.*<string>\(.*\)<\/string>.*/\1/p;}' scripts/bundle-app.sh)"
TAG="v$VERSION"
OUT="$ROOT/dist/release"
APP="$OUT/Vhrase.app"
ZIP="$OUT/Vhrase-$VERSION.zip"

[[ -z "$(git status --porcelain)" ]] || fail "Commit or stash changes first, so the release matches a commit."
[[ "$(git rev-parse -q --verify "refs/tags/$TAG^{commit}")" == "$(git rev-parse HEAD)" ]] ||
  fail "Tag $TAG, the version in bundle-app.sh, must point at HEAD."
if [[ "$DRY_RUN" == 0 ]]; then
  git fetch -q origin main
  git merge-base --is-ancestor HEAD origin/main || fail "Push main first, so the release points at a published commit."
  ! gh release view "$TAG" >/dev/null 2>&1 || fail "Release $TAG already exists."
fi

# One stable identity keeps macOS's Microphone and Accessibility grants across updates; ad-hoc signing would make every release a new app.
export VHRASE_CODESIGN_IDENTITY="${VHRASE_CODESIGN_IDENTITY:-Vhrase Local Development}"
rm -rf "$OUT"
bash scripts/bundle-app.sh release "$APP" >/dev/null
ditto -c -k --keepParent "$APP" "$ZIP"
echo "$ZIP: $(du -h "$ZIP" | cut -f1), sha256 $(shasum -a 256 "$ZIP" | cut -d ' ' -f 1)"

if [[ "$DRY_RUN" == 1 ]]; then
  echo "Dry run: $TAG was not published."
  exit 0
fi

# Notes list the commits since the last published release, since many local version tags were never released; the first release lists none.
PREVIOUS="$(gh release list --limit 1 --json tagName --jq '.[0].tagName // empty')"
NOTES="Unzip, move Vhrase to Applications, and allow it once in System Settings → Privacy & Security, since it isn't notarized."
if [[ -n "$PREVIOUS" ]]; then
  NOTES+=$'\n\n'"$(git log --format='- %s' "$PREVIOUS..$TAG")"
fi
git push origin "refs/tags/$TAG"
gh release create "$TAG" "$ZIP" --verify-tag --title "Vhrase $VERSION" --notes "$NOTES"
