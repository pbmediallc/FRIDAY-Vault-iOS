// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import CommonCrypto
import CryptoKit
import Foundation
import Security

enum OrgCryptoError: LocalizedError, Equatable, Sendable {
    case randomFailed
    case cipherFailed(Int32)
    case malformed(String)
    case keyImport(String)
    case keyGeneration(String)
    case rsa(String)
    case macMismatch

    var errorDescription: String? {
        switch self {
        case .randomFailed:
            "Der Zufallsgenerator des Systems hat keine Schlüsselbytes geliefert."
        case let .cipherFailed(code):
            "Die Verschlüsselung ist fehlgeschlagen (CommonCrypto \(code))."
        case let .malformed(what):
            "Unerwartetes Format: \(what)."
        case let .keyImport(why):
            "Der öffentliche Schlüssel des Kontos war nicht lesbar: \(why)"
        case let .keyGeneration(why):
            "Das Schlüsselpaar der Organisation konnte nicht erzeugt werden: \(why)"
        case let .rsa(why):
            "Die RSA-Verschlüsselung ist fehlgeschlagen: \(why)"
        case .macMismatch:
            "Die Prüfsumme der Chiffre stimmt nicht."
        }
    }
}

/// Bitwardens Chiffre-Vertrag, soweit das Anlegen einer Organisation ihn braucht.
///
/// * Typ 2 (`2.iv|ct|mac`): AES-256-CBC mit PKCS#7, HMAC-SHA256 über IV+Chiffre.
///   Der 64-Byte-Schlüssel teilt sich in 32 Byte Verschlüsselung und 32 Byte MAC.
/// * Typ 4 (`4.b64`): RSA-2048 mit OAEP-SHA1 — so verpackt jeder Bitwarden-Client den
///   Organisationsschlüssel für ein Mitglied.
///
/// Mehr wird hier bewusst nicht nachgebaut. Sammlungsnamen, Einträge, Bestätigen —
/// alles, was Schlüssel aus dem Tresor braucht — bleibt beim bw-Kern.
enum OrgCrypto {
    static let orgKeyLength = 64

    static func randomBytes(_ count: Int) throws -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        let status = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        guard status == errSecSuccess else { throw OrgCryptoError.randomFailed }
        return Data(bytes)
    }

    static func generateOrgKey() throws -> Data { try randomBytes(orgKeyLength) }

    // MARK: - EncString Typ 2 — AesCbc256_HmacSha256_B64

    static func encrypt(_ plaintext: Data, key: Data, iv fixedIV: Data? = nil) throws -> String {
        guard key.count == orgKeyLength else {
            throw OrgCryptoError.malformed("Organisationsschlüssel hat \(key.count) statt \(orgKeyLength) Byte")
        }
        let iv = try fixedIV ?? randomBytes(kCCBlockSizeAES128)
        guard iv.count == kCCBlockSizeAES128 else {
            throw OrgCryptoError.malformed("IV hat \(iv.count) statt \(kCCBlockSizeAES128) Byte")
        }
        let encryptionKey = Data(key.prefix(32))
        let macKey = Data(key.suffix(32))
        let ciphertext = try aes(CCOperation(kCCEncrypt), key: encryptionKey, iv: iv, input: plaintext)
        let mac = Data(HMAC<SHA256>.authenticationCode(for: iv + ciphertext, using: SymmetricKey(data: macKey)))
        return "2.\(iv.base64EncodedString())|\(ciphertext.base64EncodedString())|\(mac.base64EncodedString())"
    }

    static func encrypt(_ text: String, key: Data) throws -> String {
        try encrypt(Data(text.utf8), key: key)
    }

    static func decrypt(_ encString: String, key: Data) throws -> Data {
        guard key.count == orgKeyLength else {
            throw OrgCryptoError.malformed("Organisationsschlüssel hat \(key.count) statt \(orgKeyLength) Byte")
        }
        guard encString.hasPrefix("2.") else { throw OrgCryptoError.malformed("kein Typ-2-EncString") }
        let parts = encString.dropFirst(2)
            .split(separator: "|", omittingEmptySubsequences: false)
            .map(String.init)
        guard parts.count == 3,
              let iv = Data(base64Encoded: parts[0]),
              let ciphertext = Data(base64Encoded: parts[1]),
              let mac = Data(base64Encoded: parts[2]) else {
            throw OrgCryptoError.malformed("EncString-Teile")
        }
        let macKey = SymmetricKey(data: Data(key.suffix(32)))
        guard HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: iv + ciphertext, using: macKey) else {
            throw OrgCryptoError.macMismatch
        }
        return try aes(CCOperation(kCCDecrypt), key: Data(key.prefix(32)), iv: iv, input: ciphertext)
    }

    static func decryptString(_ encString: String, key: Data) throws -> String {
        guard let text = String(data: try decrypt(encString, key: key), encoding: .utf8) else {
            throw OrgCryptoError.malformed("Klartext ist kein UTF-8")
        }
        return text
    }

    private static func aes(_ operation: CCOperation, key: Data, iv: Data, input: Data) throws -> Data {
        var output = [UInt8](repeating: 0, count: input.count + kCCBlockSizeAES128)
        var moved = 0
        let outputCapacity = output.count
        let status: CCCryptorStatus = output.withUnsafeMutableBytes { outputPtr in
            key.withUnsafeBytes { keyPtr in
                iv.withUnsafeBytes { ivPtr in
                    input.withUnsafeBytes { inputPtr in
                        CCCrypt(
                            operation,
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyPtr.baseAddress, key.count,
                            ivPtr.baseAddress,
                            inputPtr.baseAddress, input.count,
                            outputPtr.baseAddress, outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == CCCryptorStatus(kCCSuccess) else { throw OrgCryptoError.cipherFailed(status) }
        return Data(output.prefix(moved))
    }

    // MARK: - EncString Typ 4 — Rsa2048_OaepSha1_B64

    static func rsaEncrypt(_ plaintext: Data, publicKeySPKI: Data) throws -> String {
        let pkcs1 = try DER.rsaPublicKeyPKCS1(fromSPKI: publicKeySPKI)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPublic,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error) else {
            throw OrgCryptoError.keyImport(describe(error))
        }
        return try rsaEncrypt(plaintext, publicKey: key)
    }

    static func rsaEncrypt(_ plaintext: Data, publicKey: SecKey) throws -> String {
        guard SecKeyIsAlgorithmSupported(publicKey, .encrypt, .rsaEncryptionOAEPSHA1) else {
            throw OrgCryptoError.rsa("OAEP-SHA1 wird von diesem Schlüssel nicht unterstützt")
        }
        var error: Unmanaged<CFError>?
        guard let ciphertext = SecKeyCreateEncryptedData(
            publicKey, .rsaEncryptionOAEPSHA1, plaintext as CFData, &error
        ) as Data? else {
            throw OrgCryptoError.rsa(describe(error))
        }
        return "4.\(ciphertext.base64EncodedString())"
    }

    static func rsaDecrypt(_ encString: String, privateKey: SecKey) throws -> Data {
        guard encString.hasPrefix("4."),
              let ciphertext = Data(base64Encoded: String(encString.dropFirst(2))) else {
            throw OrgCryptoError.malformed("kein Typ-4-EncString")
        }
        var error: Unmanaged<CFError>?
        guard let plaintext = SecKeyCreateDecryptedData(
            privateKey, .rsaEncryptionOAEPSHA1, ciphertext as CFData, &error
        ) as Data? else {
            throw OrgCryptoError.rsa(describe(error))
        }
        return plaintext
    }

    // MARK: - Schlüsselpaar der Organisation

    struct KeyPair {
        /// X.509 SubjectPublicKeyInfo, DER — so legt Bitwarden öffentliche Schlüssel ab.
        let publicKeySPKI: Data
        /// PKCS#8 PrivateKeyInfo, DER — wird vor dem Versand mit dem Organisationsschlüssel verpackt.
        let privateKeyPKCS8: Data
        let privateKey: SecKey
    }

    static func generateKeyPair(bits: Int = 2048) throws -> KeyPair {
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits: bits,
            kSecAttrIsPermanent: false,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            throw OrgCryptoError.keyGeneration(describe(error))
        }
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw OrgCryptoError.keyGeneration("kein öffentlicher Teil")
        }
        guard let publicPKCS1 = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw OrgCryptoError.keyGeneration(describe(error))
        }
        guard let privatePKCS1 = SecKeyCopyExternalRepresentation(privateKey, &error) as Data? else {
            throw OrgCryptoError.keyGeneration(describe(error))
        }
        return KeyPair(
            publicKeySPKI: DER.spki(fromPKCS1Public: publicPKCS1),
            privateKeyPKCS8: DER.pkcs8(fromPKCS1Private: privatePKCS1),
            privateKey: privateKey
        )
    }

    private static func describe(_ error: Unmanaged<CFError>?) -> String {
        guard let error else { return "unbekannter Fehler" }
        return CFErrorCopyDescription(error.takeRetainedValue()) as String
    }
}

/// Gerade genug ASN.1, um RSA-Schlüssel zwischen PKCS#1 (was Security.framework
/// spricht) und SPKI/PKCS#8 (was Bitwarden ablegt) umzupacken.
enum DER {
    /// `SEQUENCE { OID rsaEncryption, NULL }`
    static let rsaAlgorithmIdentifier = Data([
        0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86, 0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00,
    ])

    struct Element: Equatable {
        let tag: UInt8
        let content: Data
    }

    static func encodeLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var bytes: [UInt8] = []
        var remaining = length
        while remaining > 0 {
            bytes.insert(UInt8(remaining & 0xff), at: 0)
            remaining >>= 8
        }
        return Data([0x80 | UInt8(bytes.count)]) + Data(bytes)
    }

    static func tlv(_ tag: UInt8, _ content: Data) -> Data {
        Data([tag]) + encodeLength(content.count) + content
    }

    static func spki(fromPKCS1Public key: Data) -> Data {
        tlv(0x30, rsaAlgorithmIdentifier + tlv(0x03, Data([0x00]) + key))
    }

    static func pkcs8(fromPKCS1Private key: Data) -> Data {
        tlv(0x30, Data([0x02, 0x01, 0x00]) + rsaAlgorithmIdentifier + tlv(0x04, key))
    }

    static func elements(in data: Data) throws -> [Element] {
        let bytes = [UInt8](data)
        var index = 0
        var result: [Element] = []
        while index < bytes.count {
            let (element, next) = try readElement(bytes, at: index)
            result.append(element)
            index = next
        }
        return result
    }

    private static func readElement(_ bytes: [UInt8], at start: Int) throws -> (Element, Int) {
        guard start + 2 <= bytes.count else { throw OrgCryptoError.malformed("DER: abgeschnitten") }
        let tag = bytes[start]
        var index = start + 1
        var length = Int(bytes[index])
        index += 1
        if length & 0x80 != 0 {
            let count = length & 0x7f
            guard count > 0, count <= 4, index + count <= bytes.count else {
                throw OrgCryptoError.malformed("DER: Längenfeld")
            }
            length = 0
            for _ in 0 ..< count {
                length = (length << 8) | Int(bytes[index])
                index += 1
            }
        }
        guard index + length <= bytes.count else { throw OrgCryptoError.malformed("DER: Inhalt abgeschnitten") }
        return (Element(tag: tag, content: Data(bytes[index ..< index + length])), index + length)
    }

    /// Zieht den PKCS#1-Teil aus einem SubjectPublicKeyInfo.
    static func rsaPublicKeyPKCS1(fromSPKI spki: Data) throws -> Data {
        let outer = try elements(in: spki)
        guard outer.count == 1, outer[0].tag == 0x30 else {
            throw OrgCryptoError.malformed("SPKI: keine einzelne Sequenz")
        }
        let inner = try elements(in: outer[0].content)
        guard inner.count == 2, inner[0].tag == 0x30, inner[1].tag == 0x03 else {
            throw OrgCryptoError.malformed("SPKI: Aufbau")
        }
        guard inner[0].content == rsaAlgorithmIdentifier.dropFirst(2) else {
            throw OrgCryptoError.malformed("SPKI: kein RSA-Schlüssel")
        }
        let bits = inner[1].content
        guard bits.first == 0x00 else { throw OrgCryptoError.malformed("SPKI: BIT STRING") }
        return Data(bits.dropFirst())
    }

    /// Zieht den PKCS#1-Teil aus einem PrivateKeyInfo.
    static func rsaPrivateKeyPKCS1(fromPKCS8 pkcs8: Data) throws -> Data {
        let outer = try elements(in: pkcs8)
        guard outer.count == 1, outer[0].tag == 0x30 else {
            throw OrgCryptoError.malformed("PKCS#8: keine einzelne Sequenz")
        }
        let inner = try elements(in: outer[0].content)
        guard inner.count >= 3, inner[0].tag == 0x02, inner[1].tag == 0x30, inner[2].tag == 0x04 else {
            throw OrgCryptoError.malformed("PKCS#8: Aufbau")
        }
        return inner[2].content
    }
}
