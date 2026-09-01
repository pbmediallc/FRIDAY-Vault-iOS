// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import BitwardenKit
import BitwardenSdk
import Foundation

/// Was die Organisationsverwaltung vom Tresor braucht — auf dem iPhone geliefert vom
/// Bitwarden-SDK und den Diensten der App, nicht von einem bw-Kern.
///
/// Als Vertrag getrennt, damit Tests eine Attrappe einsetzen können.
@MainActor
protocol FridayOrgEngine: AnyObject {
    var vaultIsUnlocked: Bool { get }
    var accountEmail: String { get }

    func orgCollections(organizationID: String) async throws -> [OrgCollection]
    func orgCollectionDetails(organizationID: String, collectionID: String) async throws -> OrgCollectionDetails
    func createOrgCollection(organizationID: String, name: String) async throws
    func createOrgCollection(organizationID: String, name: String, access: OrgCollectionDetails) async throws
    func renameOrgCollection(organizationID: String, collectionID: String, name: String) async throws
    func setOrgCollectionAccess(organizationID: String, collectionID: String, access: OrgCollectionDetails) async throws
    func deleteOrgCollection(organizationID: String, collectionID: String) async throws
    func confirmOrgMember(organizationID: String, memberID: String) async throws
    func syncEngine() async throws

    func organizationItems(organizationID: String) async throws -> [OrgItem]
    func personalItems() async throws -> [OrgItem]
    func organizationTrashItems(organizationID: String) async throws -> [OrgItem]
    func moveItemToOrganization(itemID: String, organizationID: String, collectionIDs: [String]) async throws
    func setItemCollections(itemID: String, collectionIDs: [String]) async throws
    func trashItem(itemID: String) async throws
    func restoreItem(itemID: String) async throws
}

/// Die Umsetzung mit den Diensten der App.
///
/// * Sammlungsnamen: das SDK entschlüsselt und verschlüsselt sie mit dem Organisations-
///   schlüssel, den es nach dem Entsperren selbst hält.
/// * Bestätigen: braucht den rohen Organisationsschlüssel für ein Mitglied verpackt —
///   das SDK gibt ihn nicht heraus. Er wird deshalb aus dem Sync-Stand gewonnen:
///   Nutzerschlüssel (SDK) → privater RSA-Schlüssel des Kontos (Typ 2) → Organisations-
///   schlüssel (Typ 4). Dieselben Bausteine wie in der Mac-App, dort gegen Referenz-
///   vektoren geprüft.
/// * Einträge: Übernehmen, Sammlungen ändern, Papierkorb, Wiederherstellen laufen über
///   das VaultRepository — genau die Wege, die die App selbst benutzt.
@MainActor
final class FridayOrgVaultEngine: FridayOrgEngine {
    typealias Services = HasAuthRepository
        & HasClientService
        & HasStateService
        & HasSyncService
        & HasVaultRepository

    private let services: Services
    private let client: FridayOrgClient
    private var email = ""
    private var unlocked = false

    init(services: Services, client: FridayOrgClient) {
        self.services = services
        self.client = client
    }

    /// Einmal beim Öffnen: Konto und Sperrstand holen.
    func prepare() async {
        if let account = try? await services.stateService.getActiveAccount() {
            email = account.profile.email
            unlocked = !((try? await services.authRepository.isLocked(userId: account.profile.userId)) ?? true)
        }
    }

    var vaultIsUnlocked: Bool { unlocked }
    var accountEmail: String { email }

    // MARK: - Sammlungen

    func orgCollections(organizationID: String) async throws -> [OrgCollection] {
        try await services.vaultRepository.fetchCollections(includeReadOnly: true)
            .filter { $0.organizationId == organizationID }
            .map { view in
                OrgCollection(
                    id: view.id ?? "",
                    name: view.name,
                    organizationID: view.organizationId,
                    externalID: view.externalId,
                    nameIsCipher: false
                )
            }
            .filter { !$0.id.isEmpty }
    }

    func orgCollectionDetails(organizationID: String, collectionID: String) async throws -> OrgCollectionDetails {
        try await client.collectionDetails(organizationID: organizationID, collectionID: collectionID)
    }

    private func encryptName(_ name: String, organizationID: String, collectionID: String?) async throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { throw OrgEngineError.invalidName }
        let view = CollectionView(
            id: collectionID,
            organizationId: organizationID,
            name: clean,
            externalId: nil,
            hidePasswords: false,
            readOnly: false,
            manage: true,
            type: .sharedCollection
        )
        return try await services.clientService.vault().collections().encrypt(collectionView: view).name
    }

    func createOrgCollection(organizationID: String, name: String) async throws {
        try await createOrgCollection(organizationID: organizationID, name: name, access: OrgCollectionDetails())
    }

    func createOrgCollection(organizationID: String, name: String, access: OrgCollectionDetails) async throws {
        let encrypted = try await encryptName(name, organizationID: organizationID, collectionID: nil)
        try await client.createCollection(organizationID: organizationID, encryptedName: encrypted, access: access)
        try await syncEngine()
    }

    func renameOrgCollection(organizationID: String, collectionID: String, name: String) async throws {
        let current = try await client.collectionDetails(organizationID: organizationID, collectionID: collectionID)
        let encrypted = try await encryptName(name, organizationID: organizationID, collectionID: collectionID)
        try await client.updateCollection(organizationID: organizationID, collectionID: collectionID, encryptedName: encrypted, access: current)
        try await syncEngine()
    }

    func setOrgCollectionAccess(organizationID: String, collectionID: String, access: OrgCollectionDetails) async throws {
        guard let collection = try await orgCollections(organizationID: organizationID).first(where: { $0.id == collectionID }) else {
            throw OrgError.notFound
        }
        let encrypted = try await encryptName(collection.name, organizationID: organizationID, collectionID: collectionID)
        try await client.updateCollection(organizationID: organizationID, collectionID: collectionID, encryptedName: encrypted, access: access)
    }

    func deleteOrgCollection(organizationID: String, collectionID: String) async throws {
        try await client.deleteCollection(organizationID: organizationID, collectionID: collectionID)
        try await syncEngine()
    }

    // MARK: - Bestätigen

    /// Der rohe Organisationsschlüssel — aus dem, was die App nach dem Entsperren hält.
    private func organizationKey(organizationID: String) async throws -> Data {
        guard unlocked else { throw OrgEngineError.vaultLocked }
        guard let organization = try await services.vaultRepository.fetchOrganization(withId: organizationID),
              let wrappedOrgKey = organization.key else {
            throw OrgEngineError.noOrganizationKey
        }
        let userKeyB64 = try await services.clientService.crypto().getUserEncryptionKey()
        guard let userKey = Data(base64Encoded: userKeyB64), userKey.count == OrgCrypto.orgKeyLength else {
            throw OrgEngineError.noOrganizationKey
        }
        let keys = try await services.stateService.getAccountEncryptionKeys()
        let wrappedPrivateKey: String
        switch keys.cryptographicState {
        case let .v1(privateKey):
            wrappedPrivateKey = privateKey
        case let .v2(privateKey, _, _, _):
            wrappedPrivateKey = privateKey
        }
        let privatePKCS8 = try OrgCrypto.decrypt(wrappedPrivateKey, key: userKey)
        let privatePKCS1 = try DER.rsaPrivateKeyPKCS1(fromPKCS8: privatePKCS8)
        let attributes: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateWithData(privatePKCS1 as CFData, attributes as CFDictionary, &error) else {
            throw OrgEngineError.noOrganizationKey
        }
        let orgKey = try OrgCrypto.rsaDecrypt(wrappedOrgKey, privateKey: privateKey)
        guard orgKey.count == OrgCrypto.orgKeyLength else { throw OrgEngineError.noOrganizationKey }
        return orgKey
    }

    func confirmOrgMember(organizationID: String, memberID: String) async throws {
        let orgKey = try await organizationKey(organizationID: organizationID)
        let members = try await client.members(organizationID: organizationID)
        guard let member = members.first(where: { $0.id == memberID }), let userID = member.userID else {
            throw OrgError.notFound
        }
        let publicKey = try await client.publicKey(userID: userID)
        let wrapped = try OrgCrypto.rsaEncrypt(orgKey, publicKeySPKI: publicKey)
        try await client.confirmMember(organizationID: organizationID, memberID: memberID, wrappedKey: wrapped)
    }

    func syncEngine() async throws {
        try await services.syncService.fetchSync(forceSync: true, isPeriodic: false)
    }

    // MARK: - Einträge

    private func allItems() async throws -> [OrgItem] {
        var result: [OrgItem] = []
        for try await ciphers in try await services.vaultRepository.cipherPublisher() {
            result = ciphers.compactMap(Self.item(from:))
            break
        }
        return result
    }

    private static func item(from view: CipherListView) -> OrgItem? {
        guard let id = view.id else { return nil }
        let type: CipherType
        switch view.type {
        case .login: type = .login
        case .secureNote: type = .secureNote
        case .card: type = .card
        case .identity: type = .identity
        case .sshKey: type = .sshKey
        case .bankAccount: type = .bankAccount
        case .passport: type = .passport
        case .driversLicense: type = .driversLicense
        }
        return OrgItem(
            id: id,
            name: view.name,
            subtitle: view.subtitle,
            organizationID: view.organizationId,
            collectionIDs: view.collectionIds,
            type: type,
            deletedDate: view.deletedDate
        )
    }

    func organizationItems(organizationID: String) async throws -> [OrgItem] {
        try await allItems().filter { $0.organizationID == organizationID && $0.deletedDate == nil }
    }

    func personalItems() async throws -> [OrgItem] {
        try await allItems().filter { $0.organizationID == nil && $0.deletedDate == nil }
    }

    func organizationTrashItems(organizationID: String) async throws -> [OrgItem] {
        try await allItems().filter { $0.organizationID == organizationID && $0.deletedDate != nil }
    }

    private func cipherView(_ id: String) async throws -> CipherView {
        guard let view = try await services.vaultRepository.fetchCipher(withId: id) else { throw OrgError.notFound }
        return view
    }

    func moveItemToOrganization(itemID: String, organizationID: String, collectionIDs: [String]) async throws {
        guard !collectionIDs.isEmpty else { throw OrgEngineError.noCollection }
        let view = try await cipherView(itemID)
        try await services.vaultRepository.shareCipher(view, newOrganizationId: organizationID, newCollectionIds: collectionIDs)
    }

    func setItemCollections(itemID: String, collectionIDs: [String]) async throws {
        guard !collectionIDs.isEmpty else { throw OrgEngineError.noCollection }
        let view = try await cipherView(itemID)
        try await services.vaultRepository.updateCipherCollections(view.update(collectionIds: collectionIDs))
    }

    func trashItem(itemID: String) async throws {
        try await services.vaultRepository.softDeleteCipher(try await cipherView(itemID))
    }

    func restoreItem(itemID: String) async throws {
        try await services.vaultRepository.restoreCipher(try await cipherView(itemID))
    }
}
