# N2IT Phone (Android): releases

CI (`.github/workflows/android.yml`) builds on every push to `main` that touches `android/**` and replaces the moving
`latest` release. The server's sync cron (`/root/voip/n2it-app/sync-downloads.sh`, every 15 min) copies that APK to
https://voip.n2it.co.za/download/. `latest` is overwritten by the next build, so each shipped version is also kept as:

- a git tag `android-v<versionName>` on the commit CI built (tags trigger no workflow and the sync ignores them);
- a copy of the APK in `/var/backups/n2it/app/` on voip.n2it.co.za, with its SHA-256 (not served, not in git, the sync
  never touches it). To roll back, copy it over `/var/www/fusionpbx/public/download/n2it-phone.apk` and pause the sync
  cron until a fixed build is on `main`, or the next sync puts `latest` back.

## Shipping a version
1. Bump `versionCode` and `versionName` in `android/app/build.gradle.kts`, merge to `main`, wait for the build to go green.
2. Check the `latest` release points at that commit and note the APK digest (GitHub shows it per asset).
3. After the sync (or run `sync-downloads.sh`), `sha256sum` the public APK: it must match the digest.
4. Tag: `git tag -a android-v<versionName> <commit> -m "<summary>. APK sha256 <digest>"` and `git push origin android-v<versionName>`.
5. Keep the APK: `cp -p /var/www/fusionpbx/public/download/n2it-phone.apk /var/backups/n2it/app/n2it-phone-<versionName>.apk`
   and `sha256sum` it into `n2it-phone-<versionName>.apk.sha256` next to it.
6. Delete the feature branch only after the tag is pushed. Add a line below.

Keep this file outside `android/`: a change there would start a new build.

## Versions
| Version | Code | Date | Commit | APK sha256 | What changed |
|---|---|---|---|---|---|
| 0.3.4 | 30 | 2026-10-26 | `7306877` | `8d702a3b9909f24f52ab7d31cfa3574dcfa0f25addd676fd9a5240a81f258b5c` | 3-way calling: Merge joins both calls in a PBX conference room (`*30` + 7 digits). In 0.3.3 the button was a stub and never joined the calls. Merged from `android-conference` (0.3.1/0.3.2). |

Versions before 0.3.4 were not tagged or kept.
