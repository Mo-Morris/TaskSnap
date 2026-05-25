---
name: release-flow
description: Fixed release workflow for TaskSnap. Use when publishing a TaskSnap version, creating or checking date-based release tags, packaging the macOS DMG, uploading the DMG to a GitHub Release with Computer Use, and ensuring no dist directory remains in the project.
---

# TaskSnap Release Flow

Use this skill whenever the user asks to publish, release, tag, package, upload a DMG, or prepare a GitHub Release for TaskSnap.

## Version

- Default version is calculated from the release date in the user's local timezone:

```bash
TZ="${TZ:-Asia/Shanghai}" date +v%Y.%m.%d
```

- If the user explicitly provides a version, use that exact version.
- Version tags must keep the `vYYYY.MM.DD` format.

## Preflight

1. Check the worktree:

```bash
git status --short --branch
```

2. Check whether the tag already exists:

```bash
git tag --list "$VERSION"
```

3. If the tag exists, do not move or recreate it unless the user explicitly asks.
4. If the tag does not exist, create it on the intended release commit:

```bash
git tag "$VERSION"
git push origin "$VERSION"
```

5. If the tag exists but `HEAD` is not that tag's commit, do not silently package `HEAD` as that version. Either package from a temporary checkout of the tag or report the mismatch to the user.

```bash
git rev-parse HEAD
git rev-parse "$VERSION"
```

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

1. Open the release page:

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

- The expected tag exists.
- The GitHub Release has the DMG asset.
- `dist` does not exist in the project root.
