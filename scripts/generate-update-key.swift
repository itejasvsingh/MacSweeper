// One-time setup for signed updates. Run on your Mac:
//   swift scripts/generate-update-key.swift
// 1. Paste the PUBLIC key into `updatePublicKeyBase64` in Sources/UpdateChecker.swift.
// 2. Add the PRIVATE key as a GitHub Actions secret named UPDATE_SIGNING_KEY
//    (Settings → Secrets and variables → Actions). Never commit it.
import CryptoKit

let key = Curve25519.Signing.PrivateKey()
print("PUBLIC  (commit this):  \(key.publicKey.rawRepresentation.base64EncodedString())")
print("PRIVATE (secret only):  \(key.rawRepresentation.base64EncodedString())")
