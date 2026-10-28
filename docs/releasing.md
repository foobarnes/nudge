# Releasing

Releases are fully automatic. Merging a PR into `main` is the whole process.

## What happens on merge

1. **Version.** `scripts/next-version.sh` reads the squash-merge commit subjects (the PR titles) since the last `v*` tag:
   - `feat:` bumps minor.
   - Anything else bumps patch: `fix:`, `chore:`, `docs:`, and the other types.
   - `type!:` or a `BREAKING CHANGE:` footer bumps major. Before 1.0 it bumps minor instead.
   - The build number is the commit count on `main`, so it always increases.
2. **Build.** `.github/workflows/release.yml` archives a Release build on `macos-26`:
   - signed with the Developer ID certificate;
   - hardened runtime on;
   - Sparkle public key baked into `Info.plist`.
3. **Package.** A DMG is built, signed, notarized with `notarytool`, and stapled.
4. **Notes.** A draft GitHub Release is created with notes generated from the merged PRs. The notes are grouped by the label `pr-title.yml` set: Breaking changes, New, Fixes, Maintenance.
5. **Appcast.** `generate_appcast` signs the DMG with the Sparkle EdDSA key and writes `appcast.xml`, with the release notes embedded. The appcast is uploaded to the release, and then the release is published.
6. **Update.** Running copies of Nudge check `releases/latest/download/appcast.xml` hourly. They download the update in the background, install it and relaunch, which takes about a second. Permissions survive updates because the signing identity never changes.

If a run fails, nothing is published. The draft release is left behind for inspection; delete it and re-run the workflow from the Actions tab.

## PR titles

PR titles must be Conventional Commits. The `PR title` check enforces this and labels the PR. Examples:

- `feat: snooze presets in Settings` → 0.**3**.0, listed under **New**
- `fix(pill): snap flicker` → 0.2.**1**, listed under **Fixes**
- `chore: bump Sparkle` → 0.2.**1**, listed under **Maintenance**

The repo allows squash merges only, and the squash commit takes the PR title. That keeps every commit on `main` a parseable subject.

## One-time setup

You need an Apple Developer Program membership. Run `scripts/setup-release-secrets.sh` after gathering:

1. **Developer ID Application certificate (.p12).**
   1. In Xcode, open **Settings → Accounts**, select your team, then **Manage Certificates…**.
   2. Click **+** and choose **Developer ID Application**.
   3. Right-click the new certificate, choose **Export Certificate**, and set a password.
2. **App Store Connect API key (.p8)** for notarization.
   1. Go to [App Store Connect → Users and Access → Integrations → Team Keys](https://appstoreconnect.apple.com/access/integrations/api).
   2. Click **+**, choose the role **Developer**, and download the key. Apple lets you download it only once.
   3. Note the **Key ID** and the **Issuer ID**.

The script stores these repo secrets and variables:

| Name | Kind | What |
| --- | --- | --- |
| `DEVELOPER_ID_P12_BASE64`, `DEVELOPER_ID_P12_PASSWORD` | secret | Signing certificate |
| `APPLE_TEAM_ID` | secret | Read from the certificate |
| `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID` | secret | Notarization |
| `SPARKLE_ED_PRIVATE_KEY` | secret | Signs updates; a copy stays in your login keychain |
| `SPARKLE_PUBLIC_KEY` | variable | Baked into each build so apps verify updates |

**Never rotate the Sparkle key.** Installed copies trust only the key they were built with, so a new key strands them on their current version.

## Local builds

Local builds (`make build`, `make run`) are ad-hoc signed and have no Sparkle key, so the updater stays off. A dev build never replaces itself with a release.
