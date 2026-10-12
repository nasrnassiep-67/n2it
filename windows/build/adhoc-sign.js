// Ad-hoc sign the macOS app before it goes into the .dmg. Unsigned (identity: null) builds otherwise carry
// Electron's broken signature, which macOS reports as "damaged" once the app is downloaded.
// Skipped when CSC_NAME names a Developer ID (npm run dist:mac:signed): electron-builder signs and we notarise.
const { execFileSync } = require('child_process')
const path = require('path')

exports.default = async (context) => {
  if (context.electronPlatformName !== 'darwin' || process.env.CSC_NAME) return
  const app = path.join(context.appOutDir, `${context.packager.appInfo.productFilename}.app`)
  execFileSync('codesign', ['--force', '--deep', '--sign', '-', app], { stdio: 'inherit' })
}
