# iPhone distribution: Ad Hoc from GitHub (plan, 2026-10-06)

Decision: no TestFlight or App Store (no DUNS number; Linphone is GPLv3). Android and desktop clients download
from GitHub Releases. iPhones can't sideload, so they get **Ad Hoc** builds, installed from a web page.

## Apple's limits
- Needs the paid membership (the owner's individual account; no DUNS needed). Pending as of 2026-10-06.
- Every iPhone's UDID must be registered **before** the build it installs. A new client means: register, rebuild.
- 100 iPhones per membership year. Removing one frees its slot only at renewal.
- A build stops opening when its provisioning profile or the distribution certificate expires (at most 1 year).
  Rebuild before then.
- No automatic updates: clients reinstall from the same page.

## The client's journey
1. **Register the phone.** In Safari on the iPhone, open `https://n2it.voip.n2it.co.za/app/udid/`, enter name and
   company, tap *Register this iPhone*, allow the profile download, and install it under Settings > Profile
   Downloaded. The profile only reports the UDID to us and removes itself.
2. **Wait for the go-ahead.** N2IT registers the device and runs a new build (minutes).
3. **Install.** In Safari, open `https://nasrnassiep-67.github.io/n2it/install/` and tap *Install N2IT Phone*.
   It appears on the home screen.
4. **Sign in** with company code, extension and SIP password.

To verify on the first real install: whether iOS 16+ asks for Developer Mode for Ad Hoc builds (reports
differ). If it does, step 3 adds Settings > Privacy & Security > Developer Mode.

## Pieces and who builds them

### 1. UDID collection page: voip-server session (runs on the PBX web server)
Standard iOS "profile service" enrollment, served from `https://n2it.voip.n2it.co.za/app/udid/`:
- `index.php`: form (name, company, extension), then serves a `.mobileconfig` (`Content-Type:
  application/x-apple-aspen-config`) with a `Profile Service` payload whose URL is `enroll.php` and
  `DeviceAttributes` = `UDID`, `PRODUCT`, `VERSION`, `DEVICE_NAME`. Sign it with the site's TLS cert if possible,
  so iOS doesn't show "Unverified".
- `enroll.php`: iOS POSTs a CMS-signed plist. Extract the plist (`openssl smime -verify -noverify -inform DER`),
  read `UDID`/`PRODUCT`, store `name, company, product, udid, date` outside the web root, notify N2IT (email),
  then answer `301` to a "Registered, we'll let you know" page.
- Protect it from spam (rate limit, or a simple access code given to clients). UDIDs are device identifiers:
  never put them in this public repo.

### 2. Register devices + build: Mac session (GitHub Actions, `.github/workflows/ios.yml`)
- New GitHub secret `ADHOC_DEVICES`: one `Name,UDID` per line (from the list the UDID page collects).
- The `adhoc` job gains a step that registers any missing UDIDs through the App Store Connect API
  (`POST /v1/devices`, platform IOS) with the existing API key. Then it archives with cloud-managed signing
  (`-allowProvisioningUpdates`) so Xcode regenerates the Ad Hoc profile including every registered device.
- Version: `CURRENT_PROJECT_VERSION` = run number (already set), `MARKETING_VERSION` from `project.yml`.
- `aps-environment: production` (already switched in the job). Push still needs the gateway deployed.

### 3. Publish: Mac session (same workflow)
- Upload the `.ipa` to a GitHub Release `ios-latest` (replaced each build, like `latest` / `desktop-latest`).
- Generate `manifest.plist` (`items[0].assets` = `software-package` URL of the release `.ipa`;
  `metadata` = `bundle-identifier za.co.n2it.softphone`, `bundle-version`, `kind software`, `title N2IT Phone`;
  optional `display-image`/`full-size-image` from the app icon).
- Serve `docs/install/index.html` + `manifest.plist` with **GitHub Pages** (source: `docs/` on `main`, or a Pages
  deploy step). The button is `itms-services://?action=download-manifest&url=https://nasrnassiep-67.github.io/n2it/install/manifest.plist`.
  Pages gives HTTPS and correct content types. The page also shows the build number and date, and links to
  the Android APK and desktop installers, so it's the single download page for every platform.
- Fallback if iOS refuses the `.ipa` via GitHub's release redirect: copy the `.ipa` into the Pages deploy (or onto
  `voip.n2it.co.za/app/`) instead.

### 4. The owner, once the membership shows Active
1. Team ID from developer.apple.com/account > Membership details. If it isn't `69Y3USPRR5`, tell the Mac session
   (it goes in `project.yml`).
2. App Store Connect > Users and Access > Integrations > App Store Connect API: create a key with the
   **App Manager** role (needed to register devices), download the `.p8` (once only), note Key ID and Issuer ID.
3. Add the secrets yourself (the key never goes through Claude):
   ```
   gh secret set APPLE_TEAM_ID     -R nasrnassiep-67/n2it
   gh secret set ASC_KEY_ID        -R nasrnassiep-67/n2it
   gh secret set ASC_ISSUER_ID     -R nasrnassiep-67/n2it
   base64 -i AuthKey_XXXX.p8 | gh secret set ASC_KEY_P8_BASE64 -R nasrnassiep-67/n2it
   gh secret set ADHOC_DEVICES     -R nasrnassiep-67/n2it   # paste "Name,UDID" lines, Ctrl+D
   ```
4. Turn on GitHub Pages: repo Settings > Pages > Deploy from branch `main`, folder `/docs`.

## Day-to-day
- **New client:** they register on the UDID page. You add the line to `ADHOC_DEVICES` and run
  Actions > "iOS build" > Run workflow (adhoc ✓). Tell the client to install. Existing clients needn't reinstall:
  their old build keeps working.
- **App update:** merge to main, run the adhoc workflow, and tell clients to reinstall from the page.
- **Yearly:** renew the membership, rebuild, everyone reinstalls. Device slots reset at renewal.

## First run (test on the owner's and Royston's phones)
1. Secrets in, Pages on. Register the two UDIDs: `00008150-000D393E3EC2401C` (owner, iPhone 17) and
   `00008101-00190C112142001E` (Royston, iPhone 12).
2. Run the adhoc job and install from the Pages link on both phones. Delete the 7-day Personal Team copies first
   (same bundle id, different signer).
3. Check: installs without a cable, opens, registers, calls. Note whether Developer Mode was needed.

## Licensing (not legal advice)
The repo is public with no LICENSE. Distributing apps that link Linphone (GPLv3) without Belledonne's commercial
license generally requires the app's source under GPLv3: add a GPLv3 `LICENSE`, or buy the commercial license.
GPL software distributed through Apple's signing is a debated area; Ad Hoc carries the same question as the
App Store, with less exposure.
