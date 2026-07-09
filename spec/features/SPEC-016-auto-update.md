---
id: SPEC-016
title: Auto-Update
status: APPROVED
created: 2026-07-08
updated: 2026-07-08
gate: G1
---

## Goal

Allow the plugin to detect when a newer release is available on GitHub and apply the update in-place on the device, so users never have to manually download and reinstall the plugin.

## Background

The plugin is distributed as a ZIP archive via GitHub Releases (see `.github/workflows/release.yml`). Each release is tagged with a semver string (e.g. `v0.9.0`) that the CI pipeline injects into `_meta.lua` at build time, replacing the placeholder `version = 1`. Users currently have no in-plugin way to discover or apply a new version — they must check GitHub manually, download the zip, and copy files to their device.

The GitHub REST API exposes a public (unauthenticated) endpoint that returns the latest release for a repository: `GET https://api.github.com/repos/{owner}/{repo}/releases/latest`. The response includes `tag_name` (the version string) and the download URL for each release asset.

Applying the update is a two-step shell operation: download the zip to a temp file using the existing `ssl.https` / `ltn12` HTTP stack, then extract it over the plugin directory using `unzip -o`, which is available on all supported KOReader platforms (Kindle, Kobo, PocketBook). KOReader must then be restarted for the new Lua files to take effect.

Dev builds (where `_meta.lua` still contains the placeholder `version = 1`) must skip the auto-check entirely to avoid false update prompts during development.

## Scope

### In scope
- A `"🔄  Check for updates"` item in the Settings screen
- An automatic once-per-session update check on plugin initialisation (skipped for dev builds)
- Calling `GET https://api.github.com/repos/{owner}/{repo}/releases/latest` to retrieve the latest tag and asset download URL
- Comparing the current version against the latest tag using semver component ordering
- Downloading the release ZIP to a temporary file via `ssl.https`
- Extracting the ZIP over the plugin directory using `os.execute("unzip -o ...")`
- Showing a restart prompt after a successful update
- A new `Updater` module (`updater.lua`) encapsulating all update logic
- A settings key `auto_update_check` (boolean, default `true`) to allow users to disable the startup check

### Out of scope
- Automatic (unattended) installation without user confirmation
- Delta / patch updates (always full ZIP replacement)
- Rollback to a previous version
- Update checks for KOReader itself
- Signature or checksum verification of the downloaded ZIP (GitHub's HTTPS provides transport security)

## Requirements

1. The plugin **MUST** define a single constant `GITHUB_RELEASES_URL` in `updater.lua` as `"https://api.github.com/repos/ramonhpr/todoist.koplugin/releases/latest"`; all update requests **MUST** use this constant.
2. On plugin initialisation, if `auto_update_check` is `true` and the current version is not the dev placeholder (`1`), the plugin **MUST** perform a background update check without blocking the task list from rendering.
3. The Settings screen **MUST** include a `"🔄  Check for updates"` menu item that triggers an immediate foreground update check regardless of `auto_update_check`.
4. An update check **MUST** call `GET {GITHUB_RELEASES_URL}` and parse the `tag_name` field from the JSON response to obtain the latest available version.
5. Version comparison **MUST** use semver component ordering (major → minor → patch as integers) so that `v0.10.0` is correctly identified as newer than `v0.9.0`; leading `v` characters **MUST** be stripped before parsing.
6. If the latest tag is equal to or older than the current version, the plugin **MUST** do nothing for background checks; for a manually triggered check it **MUST** show a brief `InfoMessage`: `"KO-Tasks is up to date (v{current})"`.
7. If the latest tag is newer, the plugin **MUST** show a `ConfirmBox` displaying the current version, the available version, and buttons **Update** and **Later**.
8. Tapping **Later** **MUST** dismiss the dialog and take no further action.
9. Tapping **Update** **MUST**:
   a. Show a loading `InfoMessage` `"Downloading update…"`.
   b. Download the release ZIP asset to a temporary file path inside KOReader's cache directory.
   c. Run `unzip -o <temp_zip> -d <plugin_parent_dir>` via `os.execute` to extract the new files over the existing plugin directory.
   d. Delete the temporary ZIP file.
   e. Show an `InfoMessage` `"Update applied — please restart KOReader."` with no auto-timeout.
10. If the update check request fails (network error, non-200 response, JSON parse error), the plugin **MUST** silently ignore the failure for background checks; for a manually triggered check it **MUST** show a brief error notice.
11. If the download or extraction step fails, the plugin **MUST** show an error notice, delete any partial temp file, and leave the existing plugin files untouched.
12. If the device is offline when the user taps `"🔄  Check for updates"`, the plugin **MUST** show a notice `"Update check requires an internet connection."` and **MUST NOT** attempt any network request.
13. The `auto_update_check` toggle **MUST** be readable and writable via the Settings screen; its label **MUST** read `"Auto-check for updates:  Enabled ✓"` or `"Auto-check for updates:  Disabled"`.
14. An update check **MUST NOT** run more than once per session; subsequent calls within the same session **MUST** be no-ops for background checks.

## Edge Cases

- Current version is `1` (dev build): all update checks **MUST** be skipped silently; the `"🔄  Check for updates"` button **MUST** show `"Update checks are disabled in dev builds."` instead of hitting the network.
- The GitHub API returns a `tag_name` that cannot be parsed as semver (e.g. a pre-release tag like `v1.0.0-beta.1`): treat it as not newer than the current version and do nothing.
- The release ZIP asset URL is absent from the response (e.g. a draft release with no uploaded file): show `"Update available but no download found."` and do nothing further.
- `unzip` is not available on the device: the `os.execute` call will return a non-zero exit code; treat this as an extraction failure per Req 11.
- The user taps **Update** and loses Wi-Fi mid-download: the partial temp file **MUST** be deleted and an error notice shown; the existing plugin files **MUST** remain intact.
- The plugin directory path contains spaces: the `unzip` shell command **MUST** quote all paths to handle this correctly.
- The user manually triggers a check while a background check is already in progress: the second call **MUST** be a no-op.

## Open Questions

<!-- None — all questions resolved.
     Repository: ramonhpr/todoist.koplugin (confirmed via git remote -v).
     Release notes will not be shown in the update confirmation dialog. -->

## Related

- `_meta.lua` — `version` field compared against the latest release tag
- `ui/settings.lua` — `"🔄  Check for updates"` button and `auto_update_check` toggle (Req 3, 13)
- `.github/workflows/release.yml` — defines the release ZIP name and version injection
- SPEC-003 — Settings screen (new items added here)
- SPEC-014 — Brand compliance (plugin name used in update messages)
- ADR-001 — API authentication (update requests use the same `ssl.https` stack; no Bearer token required for GitHub public API)
