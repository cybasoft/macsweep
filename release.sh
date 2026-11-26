#!/usr/bin/env bash
set -euo pipefail

TAG="${1:?usage: release.sh vX.Y.Z [--publish]}"
VERSION="${TAG#v}"
PUBLISH="${2:-}"

[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "tag must look like v1.2.3"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "working tree not clean"; exit 1; }

REPO_DIR=$(cd "$(dirname "$0")" && pwd)
OUT_DIR="$REPO_DIR/.temp"
mkdir -p "$OUT_DIR"
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

printf "Building MacSweep %s release...\n" "$VERSION"

STAGE_DIR="$WORK_DIR/macsweep"
mkdir -p "$STAGE_DIR/core"

cp "$REPO_DIR/macsweep.sh" "$STAGE_DIR/macsweep"
cp "$REPO_DIR/modules.tsv" "$STAGE_DIR/"
cp -r "$REPO_DIR/core"/* "$STAGE_DIR/core/"
chmod 0755 "$STAGE_DIR/macsweep"

TARBALL="$WORK_DIR/macsweep-$VERSION.tar.gz"
tar -C "$WORK_DIR" -czf "$TARBALL" macsweep/

CHECKSUM=$(shasum -a 256 "$TARBALL" | awk '{print $1}')
printf "SHA-256: %s\n" "$CHECKSUM"

ARTIFACT="$OUT_DIR/macsweep-$VERSION.tar.gz"
cp "$TARBALL" "$ARTIFACT"
printf "Release artifact: %s\n" "$ARTIFACT"
printf "Checksum: %s\n" "$CHECKSUM"

if [[ "$PUBLISH" == "--publish" ]]; then
  printf "\nPublishing to GitHub...\n"
  git tag -a "$TAG" -m "macsweep $VERSION" || {
    printf "Tag %s already exists. Skipping tag creation.\n" "$TAG" >&2
  }
  git push origin "$TAG" 2>/dev/null || printf "Tag already pushed.\n" >&2
  
  gh release create "$TAG" "$ARTIFACT" \
    --title "macsweep $VERSION" \
    --notes "MacSweep $VERSION: modular macOS utility toolbox with core CLI and optional modules." \
    --verify-tag 2>/dev/null || {
    printf "Release %s already exists. Uploading artifact...\n" "$TAG" >&2
    gh release upload "$TAG" "$ARTIFACT" --clobber
  }
  
  printf "\n✓ Published macsweep-%s\n" "$VERSION"
  printf "Release URL: https://github.com/cybasoft/macsweep/releases/tag/%s\n" "$TAG"
fi