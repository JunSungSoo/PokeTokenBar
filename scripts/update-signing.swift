// Ed25519 helper for GitHub update manifests. The private key arrives on stdin, never argv.
// Usage: xcrun swift scripts/update-signing.swift new-key | public-key | sign <file> | verify <key> <file> <sig>
import CryptoKit
import Foundation

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func readPrivateKey() -> Curve25519.Signing.PrivateKey {
    guard let line = readLine(strippingNewline: true),
          let raw = Data(base64Encoded: line.trimmingCharacters(in: .whitespaces)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
        fail("A base64 Ed25519 private key is required on stdin")
    }
    return key
}

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case "new-key":
    let key = Curve25519.Signing.PrivateKey()
    print(key.rawRepresentation.base64EncodedString())
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "public-key":
    print(readPrivateKey().publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count == 2, let data = FileManager.default.contents(atPath: Array(arguments)[1]) else {
        fail("sign requires a readable file")
    }
    let key = readPrivateKey()
    guard let signature = try? key.signature(for: data) else { fail("Signing failed") }
    print(signature.base64EncodedString())
case "verify":
    let values = Array(arguments)
    guard values.count == 4, let file = FileManager.default.contents(atPath: values[2]),
          let signatureText = try? String(contentsOfFile: values[3], encoding: .utf8),
          let signature = Data(base64Encoded: signatureText.trimmingCharacters(in: .whitespacesAndNewlines)),
          let publicKey = Data(base64Encoded: values[1]),
          let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
        fail("verify requires <public-key> <file> <signature-file>")
    }
    guard key.isValidSignature(signature, for: file) else { fail("Signature does not match the public key") }
    print("signature ok")
default:
    fail("Usage: update-signing.swift new-key | public-key | sign <file> | verify <public-key> <file> <signature-file>")
}
