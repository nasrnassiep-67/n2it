// After `npm run dist:mac` with a Developer ID (CSC_NAME): sign each .dmg, send it to Apple's notary service and
// staple the ticket, so macOS opens the app without "Apple could not verify…". Needs the notary password in the
// Keychain once: xcrun notarytool store-credentials n2it-notary --apple-id <Apple ID> --team-id 8URJCQ48GM
// CI (windows.yml mac job) passes APPLE_ID + APPLE_APP_SPECIFIC_PASSWORD instead. GitHub secrets for CI:
//   MAC_CERT_P12_BASE64 (Developer ID Application cert + key exported from Keychain as .p12, base64), MAC_CERT_PASSWORD,
//   APPLE_ID, APPLE_APP_SPECIFIC_PASSWORD.
const { execFileSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const dist = path.join(__dirname, '..', 'dist')
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' })
for (const f of fs.readdirSync(dist).filter((f) => f.endsWith('.dmg'))) {
  const dmg = path.join(dist, f)
  run('codesign', ['--force', '--sign', `Developer ID Application: ${process.env.CSC_NAME || 'Nasr Nassiep (8URJCQ48GM)'}`, '--timestamp', dmg])
  const auth = process.env.APPLE_ID && process.env.APPLE_APP_SPECIFIC_PASSWORD
    ? ['--apple-id', process.env.APPLE_ID, '--password', process.env.APPLE_APP_SPECIFIC_PASSWORD, '--team-id', '8URJCQ48GM']
    : ['--keychain-profile', process.env.NOTARY_PROFILE || 'n2it-notary']
  run('xcrun', ['notarytool', 'submit', dmg, ...auth, '--wait'])
  run('xcrun', ['stapler', 'staple', dmg])
  run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '-v', dmg])
}
