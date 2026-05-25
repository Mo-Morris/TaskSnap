---
name: release-flow
description: Fixed release workflow for TaskSnap. Use when publishing a TaskSnap version, creating or checking date-based release tags, packaging the macOS DMG, uploading the DMG to a GitHub Release with Computer Use, and ensuring no dist directory remains in the project.
---

# TaskSnap Release Flow

Use this skill whenever the user asks to publish, release, tag, package, upload a DMG, or prepare a GitHub Release for TaskSnap.

## Version

- **Base version** (before collision resolution):
  - Default: release date in the user's local timezone:

```bash
TZ="${TZ:-Asia/Shanghai}" date +v%Y.%m.%d
```

  - If the user explicitly provides a version, use that string as the base (must start with `v` and match `vYYYY.MM.DD` or an existing project suffix pattern like `vYYYY.MM.DD.N`).
- **Resolved version**: the first tag name that does not exist locally or on `origin`, by appending `.1`, `.2`, … to the base when needed.
  - Example: `v2026.05.25` exists → use `v2026.05.25.1`; that also exists → `v2026.05.25.2`.
- Always set `VERSION` to the **resolved** value before tagging, packaging, or uploading. Tell the user which base was chosen and which suffix was applied, if any.

Resolve with:

```bash
BASE_VERSION="${BASE_VERSION:-$(TZ="${TZ:-Asia/Shanghai}" date +v%Y.%m.%d)}"

tag_exists() {
  git rev-parse "$1" >/dev/null 2>&1 \
    || git ls-remote --exit-code origin "refs/tags/$1" >/dev/null 2>&1
}

VERSION="$BASE_VERSION"
n=1
while tag_exists "$VERSION"; do
  VERSION="${BASE_VERSION}.${n}"
  n=$((n + 1))
done
echo "Base: $BASE_VERSION → Release: $VERSION"
```

- Do not move, delete, or recreate an existing tag unless the user explicitly asks.
- Only create a **new** tag at the resolved `VERSION` on the intended release commit (usually `HEAD`).

## Preflight

1. Check the worktree:

```bash
git status --short --branch
```

2. Run the version resolution above; export `VERSION` for all following steps.

3. Create the new tag on the intended release commit and push:

```bash
git tag "$VERSION"
git push origin "$VERSION"
```

4. If the user asks to **repackage an older tag** (not a new release), skip version resolution. Use their named tag and a temporary worktree (see Package) so the binary matches that tag—do not bump the version for repackaging only.

## Package

Use the project packaging command:

```bash
./scripts/package-dmg.sh "$VERSION"
```

The script prints the generated DMG path. It should be under `/tmp/TaskSnap-release-*`, not inside the repository.

When packaging an existing tag from a newer working tree, use a temporary worktree so the binary matches the tag:

```bash
TMP_WORKTREE="$(mktemp -d "/tmp/TaskSnap-worktree-${VERSION}.XXXXXX")"
git worktree add --detach "$TMP_WORKTREE" "$VERSION"
(cd "$TMP_WORKTREE" && ./scripts/package-dmg.sh "$VERSION")
git worktree remove "$TMP_WORKTREE"
```

If the existing tag is older than the packaging script, copy the current script into the temporary worktree and use it as tooling only:

```bash
mkdir -p "$TMP_WORKTREE/scripts"
cp scripts/package-dmg.sh "$TMP_WORKTREE/scripts/package-dmg.sh"
chmod +x "$TMP_WORKTREE/scripts/package-dmg.sh"
(cd "$TMP_WORKTREE" && ./scripts/package-dmg.sh "$VERSION")
git worktree remove --force "$TMP_WORKTREE"
```

## GitHub Release

1. Open the release page for the **resolved** version:

```text
https://github.com/Mo-Morris/TaskSnap/releases/tag/$VERSION
```

2. Use Computer Use for the upload step when the user asks for browser/UI upload.
3. Before uploading, check whether an asset named `TaskSnap-$VERSION.dmg` already exists.
4. If the asset already exists, do not upload a duplicate. Report that the release asset is already present.
5. If the asset is missing, edit the release and upload the generated DMG file.

## Cleanup

- The project must not retain a `dist` directory after release.
- Remove repo-local release output if it appears:

```bash
rm -rf dist
```

- Temporary `/tmp/TaskSnap-release-*` directories may be removed after upload if no longer needed.

## Verification

Run:

```bash
swift test
```

Confirm:

- The resolved tag exists and points at the intended commit.
- The GitHub Release for `$VERSION` has the DMG asset.
- `dist` does not exist in the project root.
