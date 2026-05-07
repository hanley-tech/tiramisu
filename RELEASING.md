# Releasing Tiramisu

Tag-based releases. No feature branches. Solo-on-`main`, hotfix-from-tag.

## Cut a release

```bash
# 1. Make sure main is green
./scripts/ai-check.sh --with-ui

# 2. Tag and push
git tag -a v0.1.0 -m "v0.1.0"
git push origin v0.1.0
```

The push of a `v*` tag fires `.github/workflows/release.yml`, which:

1. Re-runs the full test suite (gates the release on green).
2. Archives `Tiramisu.app` in Release configuration.
3. (Once an Apple Developer ID cert is configured) signs and notarizes.
4. Builds a `.dmg` with `create-dmg`.
5. Drafts a GitHub Release with the DMG + the HTML test report attached.

Until signing is configured the workflow uploads an unsigned `.app` —
useful for internal testing, not for public download.

## Versioning

Use SemVer:

- **0.x.y** — pre-1.0, breaking changes allowed in minor bumps
- **bug fix** → bump `y` (`v0.1.1`)
- **feature** → bump `x` (`v0.2.0`)
- **breaking** → bump major once we're past 1.0

The version comes from the git tag — you don't need to edit `project.yml`
or any plist for the version number.

## Hotfix on a shipped tag

When `v0.1.0` is in users' hands and you need to ship a fix without dragging
in everything that's landed on `main` since:

```bash
# Branch from the tag, not main
git checkout -b hotfix/v0.1.1 v0.1.0

# Make the fix, commit, test
./scripts/ai-check.sh
git commit -am "fix: <thing>"

# Tag and push
git tag -a v0.1.1 -m "v0.1.1 — hotfix: <thing>"
git push origin v0.1.1

# Get the fix back into main
git checkout main
git cherry-pick <hotfix-commit-sha>
git push
```

The hotfix branch can be deleted after; the tag is the permanent reference.

## Drafting release notes

The workflow drafts the release with auto-generated notes — review and
publish manually via `gh release edit v0.1.0 --draft=false` or in the GitHub UI.

For larger releases, write a markdown summary covering:

- What's new (user-facing)
- Bug fixes (user-facing)
- Breaking changes (if any)
- Known issues

Skip internal refactors and CI tweaks — link to the PR/commit list for those.

## Apple signing & notarization (TODO)

The release workflow has commented-out steps for signing + notarizing.
Activate them by:

1. Acquiring an Apple Developer ID Application certificate.
2. Setting these GitHub repo secrets:
   - `APPLE_DEVELOPER_ID_APP_CERT` — base64-encoded `.p12`
   - `APPLE_DEVELOPER_ID_APP_PASSWORD` — `.p12` password
   - `APPLE_NOTARIZE_APPLE_ID` — Apple ID email
   - `APPLE_NOTARIZE_TEAM_ID` — team ID
   - `APPLE_NOTARIZE_APP_PASSWORD` — app-specific password
3. Uncommenting the `Import Developer ID cert`, `Codesign`, and `Notarize`
   steps in `.github/workflows/release.yml`.

Until then, ship the unsigned DMG with a "right-click → Open" instruction
in the release notes — it'll work for users willing to bypass Gatekeeper.

## What lives where

- `.github/workflows/release.yml` — the release pipeline
- `.github/workflows/test.yml` — runs on every push/PR
- `scripts/ai-check.sh` — local equivalent of the CI test job
- `build/test-report.html` — the artifact attached to every release
