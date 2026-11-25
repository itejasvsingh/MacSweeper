// Signs a release zip for MacSweeper's in-app updater.
// Usage: UPDATE_SIGNING_KEY=<base64 private key> swift scripts/sign-update.swift dist/MacSweeper.zip
// Prints the base64 Ed25519 signature to stdout.
import Foundation
import CryptoKit

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write("usage: sign-update.swift <file>\n".data(using: .utf8)!)
    exit(2)
}
guard let keyB64 = ProcessInfo.processInfo.environment["UPDATE_SIGNING_KEY"],
      let keyData = Data(base64Encoded: keyB64.trimmingCharacters(in: .whitespacesAndNewlines)),
      let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: keyData) else {
    FileHandle.standardError.write("UPDATE_SIGNING_KEY is missing or invalid\n".data(using: .utf8)!)
    exit(1)
}

let file = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
let signature = try key.signature(for: file)
print(signature.base64EncodedString())
