// After `npm run dist:mac` with a Developer ID (CSC_NAME): sign each .dmg, send it to Apple's notary service and
// staple the ticket, so macOS opens the app without "Apple could not verify…". Needs the notary password in the
// Keychain once: xcrun notarytool store-credentials n2it-notary --apple-id <Apple ID> --team-id 8URJCQ48GM
const { execFileSync } = require('child_process')
const fs = require('fs')
const path = require('path')

const dist = path.join(__dirname, '..', 'dist')
const run = (cmd, args) => execFileSync(cmd, args, { stdio: 'inherit' })
for (const f of fs.readdirSync(dist).filter((f) => f.endsWith('.dmg'))) {
  const dmg = path.join(dist, f)
  run('codesign', ['--force', '--sign', `Developer ID Application: ${process.env.CSC_NAME || 'Nasr Nassiep (8URJCQ48GM)'}`, '--timestamp', dmg])
  run('xcrun', ['notarytool', 'submit', dmg, '--keychain-profile', process.env.NOTARY_PROFILE || 'n2it-notary', '--wait'])
  run('xcrun', ['stapler', 'staple', dmg])
  run('spctl', ['--assess', '--type', 'open', '--context', 'context:primary-signature', '-v', dmg])
}
