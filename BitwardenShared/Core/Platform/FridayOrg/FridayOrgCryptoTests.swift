// swiftlint:disable line_length force_unwrapping

import Security
import XCTest
@testable import BitwardenShared

/// Prüfstand für die Chiffre, mit der eine Organisation angelegt wird.
///
/// Der Referenzvektor für Typ 2 stammt aus einer unabhängigen Rechnung (openssl
/// `enc -aes-256-cbc` + HMAC-SHA256 in Python) — nicht aus diesem Code selbst.
final class FridayOrgCryptoTests: XCTestCase {
    private let key = Data((0 ..< 64).map { UInt8($0) })
    private let iv = Data((0x10 ..< 0x20).map { UInt8($0) })

    func testType2KnownAnswer() throws {
        let enc = try OrgCrypto.encrypt(Data("Standard-Sammlung".utf8), key: key, iv: iv)
        XCTAssertEqual(
            enc,
            "2.EBESExQVFhcYGRobHB0eHw==|AMrp1izUH/AmXlmK7Pln5Csp+L7FN+EHZZvR9PU8nYs=|r63nd0eKE/Cei9FuQxpnQ3/4I8fLR/g36qp6tsFUA8s="
        )
        XCTAssertEqual(try OrgCrypto.decryptString(enc, key: key), "Standard-Sammlung")
    }

    func testType2RoundTripWithRandomKeyAndIV() throws {
        let orgKey = try OrgCrypto.generateOrgKey()
        XCTAssertEqual(orgKey.count, 64)
        let text = "Technik · Vertrieb — Umlaute äöü"
        let enc = try OrgCrypto.encrypt(text, key: orgKey)
        XCTAssertTrue(enc.hasPrefix("2."))
        XCTAssertEqual(enc.split(separator: "|").count, 3)
        XCTAssertEqual(try OrgCrypto.decryptString(enc, key: orgKey), text)
        // Zwei Verschlüsselungen desselben Texts unterscheiden sich — der IV ist zufällig.
        XCTAssertNotEqual(enc, try OrgCrypto.encrypt(text, key: orgKey))
    }

    func testTamperedCiphertextIsRejected() throws {
        let enc = try OrgCrypto.encrypt("geheim", key: key)
        var parts = enc.dropFirst(2).split(separator: "|").map(String.init)
        var ciphertext = Data(base64Encoded: parts[1])!
        ciphertext[0] ^= 0x01
        parts[1] = ciphertext.base64EncodedString()
        let tampered = "2." + parts.joined(separator: "|")
        XCTAssertThrowsError(try OrgCrypto.decrypt(tampered, key: key)) { error in
            XCTAssertEqual(error as? OrgCryptoError, .macMismatch)
        }
    }

    func testWrongKeyLengthIsRefused() {
        XCTAssertThrowsError(try OrgCrypto.encrypt("x", key: Data(repeating: 1, count: 32)))
    }

    /// Der Organisationsschlüssel wird für das Konto mit RSA verpackt — und muss mit dem
    /// privaten Schlüssel des Kontos wieder herauskommen. Der Weg über SPKI ist der,
    /// den der Server tatsächlich liefert.
    func testOrgKeyWrappedForAccountUnwrapsAgain() throws {
        let account = try OrgCrypto.generateKeyPair()
        let orgKey = try OrgCrypto.generateOrgKey()
        let wrapped = try OrgCrypto.rsaEncrypt(orgKey, publicKeySPKI: account.publicKeySPKI)
        XCTAssertTrue(wrapped.hasPrefix("4."))
        XCTAssertEqual(try OrgCrypto.rsaDecrypt(wrapped, privateKey: account.privateKey), orgKey)
    }

    /// SPKI/PKCS#8-Umverpackung: was hineingeht, kommt wieder heraus, und die Länge
    /// entspricht dem, was ein echter Server für 2048 Bit meldet (294 Byte SPKI).
    func testKeyContainersRoundTrip() throws {
        let pair = try OrgCrypto.generateKeyPair()
        XCTAssertEqual(pair.publicKeySPKI.count, 294)
        XCTAssertEqual(pair.publicKeySPKI.base64EncodedString().count, 392)

        var error: Unmanaged<CFError>?
        let publicKey = try XCTUnwrap(SecKeyCopyPublicKey(pair.privateKey))
        let publicPKCS1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(publicKey, &error) as Data?)
        let privatePKCS1 = try XCTUnwrap(SecKeyCopyExternalRepresentation(pair.privateKey, &error) as Data?)

        XCTAssertEqual(try DER.rsaPublicKeyPKCS1(fromSPKI: pair.publicKeySPKI), publicPKCS1)
        XCTAssertEqual(try DER.rsaPrivateKeyPKCS1(fromPKCS8: pair.privateKeyPKCS8), privatePKCS1)
    }

    func testDERLengthEncoding() {
        XCTAssertEqual(DER.encodeLength(5), Data([0x05]))
        XCTAssertEqual(DER.encodeLength(0x7f), Data([0x7f]))
        XCTAssertEqual(DER.encodeLength(0x80), Data([0x81, 0x80]))
        XCTAssertEqual(DER.encodeLength(0x1234), Data([0x82, 0x12, 0x34]))
    }

    func testBrokenSPKIIsRefusedNotGuessed() {
        XCTAssertThrowsError(try DER.rsaPublicKeyPKCS1(fromSPKI: Data([0x30, 0x03, 0x02, 0x01, 0x00])))
        XCTAssertThrowsError(try DER.rsaPublicKeyPKCS1(fromSPKI: Data()))
        XCTAssertThrowsError(try OrgCrypto.rsaEncrypt(Data("x".utf8), publicKeySPKI: Data([0x00, 0x01])))
    }

    /// Der private Schlüssel der Organisation liegt als PKCS#8 unter dem Organisations-
    /// schlüssel — nach dem Auspacken muss er wieder ein brauchbarer Schlüssel sein.
    func testEncryptedPrivateKeyRestoresToWorkingKey() throws {
        let pair = try OrgCrypto.generateKeyPair()
        let orgKey = try OrgCrypto.generateOrgKey()
        let enc = try OrgCrypto.encrypt(pair.privateKeyPKCS8, key: orgKey)
        let restoredPKCS8 = try OrgCrypto.decrypt(enc, key: orgKey)
        let pkcs1 = try DER.rsaPrivateKeyPKCS1(fromPKCS8: restoredPKCS8)

        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        let restored = try XCTUnwrap(SecKeyCreateWithData(pkcs1 as CFData, attributes as CFDictionary, &error))
        let probe = try OrgCrypto.rsaEncrypt(Data("Probe".utf8), publicKeySPKI: pair.publicKeySPKI)
        XCTAssertEqual(try OrgCrypto.rsaDecrypt(probe, privateKey: restored), Data("Probe".utf8))
    }
}
