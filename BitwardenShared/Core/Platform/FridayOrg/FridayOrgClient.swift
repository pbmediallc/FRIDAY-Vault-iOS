// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import Foundation
import Networking

enum OrgError: LocalizedError, Equatable, Sendable {
    case notAuthenticated
    case unauthorized
    case forbidden
    case notFound
    case server(String)
    case transport(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notAuthenticated:
            "Die Verbindung zur Organisation besteht nicht mehr. Bitte erneut öffnen."
        case .unauthorized:
            "Der Server hat den Zugang abgelehnt. Entweder ist die Sitzung abgelaufen, oder dieses Konto darf diese Organisation nicht verwalten."
        case .forbidden:
            "Dieses Konto darf die Organisation nicht verwalten. Dafür braucht es Eigentümer- oder Administratorrechte."
        case .notFound:
            "Der Server kennt diesen Endpunkt nicht. Diese Vaultwarden-Fassung kann das vermutlich nicht."
        case let .server(message):
            message
        case let .transport(message):
            "Der Server war nicht erreichbar (\(message))."
        case .invalidResponse:
            "Die Antwort des Servers war nicht lesbar."
        }
    }
}

/// Die Organisations-Schnittstelle von Bitwarden, angemeldet als das Konto der App.
///
/// Auf dem iPhone gibt es keinen zweiten Schlüssel und keinen bw-Kern: die App ist
/// schon angemeldet, ihr `HTTPService` hängt das Token an und erneuert es bei 401.
/// Dieser Client trägt nur Pfade und Nutzlasten — dieselben wie in der Mac-App.
actor FridayOrgClient {
    private let http: HTTPService
    private let baseURL: URL

    init(http: HTTPService, baseURL: URL) {
        self.http = http
        self.baseURL = baseURL
    }

    // MARK: - Konto

    func profile() async throws -> OrgProfile {
        let data = try await get("/api/accounts/profile")
        guard let profile = try OrgParser.profile(from: data) else { throw OrgError.invalidResponse }
        return profile
    }

    /// Der öffentliche RSA-Schlüssel eines Kontos (SubjectPublicKeyInfo, DER).
    func publicKey(userID: String) async throws -> Data {
        let data = try await get("/api/users/\(userID)/public-key")
        guard let key = try OrgParser.publicKey(from: data) else { throw OrgError.invalidResponse }
        return key
    }

    // MARK: - Organisation

    func organization(id: String) async throws -> OrgSummary {
        let data = try await get("/api/organizations/\(id)")
        guard let summary = try OrgParser.organization(from: data) else { throw OrgError.invalidResponse }
        return summary
    }

    func updateOrganization(id: String, name: String, billingEmail: String) async throws {
        _ = try await send("/api/organizations/\(id)", method: .put, body: ["name": name, "billingEmail": billingEmail])
    }

    // MARK: - Mitglieder

    func members(organizationID: String) async throws -> [OrgMember] {
        let data = try await get("/api/organizations/\(organizationID)/users?includeCollections=true&includeGroups=true")
        return try OrgParser.members(from: data)
    }

    /// `accessAll` ist bewusst immer `false`: neuere Vaultwarden-Fassungen kennen es nicht
    /// mehr, und wo es noch gilt, darf ein Mitglied nicht heimlich jede Sammlung bekommen.
    func invite(organizationID: String, emails: [String], role: OrgMemberRole, collections: [OrgCollectionAccess], groups: [String]) async throws {
        let payload: [String: Any] = [
            "emails": emails,
            "type": role.rawValue,
            "accessAll": false,
            "collections": collections.map(Self.accessPayload),
            "groups": groups,
            "permissions": NSNull(),
        ]
        _ = try await send("/api/organizations/\(organizationID)/users/invite", method: .post, body: payload)
    }

    func resendInvite(organizationID: String, memberID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)/reinvite", method: .post, body: nil)
    }

    func updateMember(organizationID: String, memberID: String, role: OrgMemberRole, collections: [OrgCollectionAccess], groups: [String]) async throws {
        let payload: [String: Any] = [
            "type": role.rawValue,
            "accessAll": false,
            "collections": collections.map(Self.accessPayload),
            "groups": groups,
            "permissions": NSNull(),
        ]
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)", method: .put, body: payload)
    }

    /// Bestätigt ein Mitglied: der Organisationsschlüssel, mit dem öffentlichen Schlüssel
    /// des Mitglieds verpackt (Typ 4), geht als `key` an den Server.
    func confirmMember(organizationID: String, memberID: String, wrappedKey: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)/confirm", method: .post, body: ["key": wrappedKey])
    }

    func revokeMember(organizationID: String, memberID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)/revoke", method: .put, body: nil)
    }

    func restoreMember(organizationID: String, memberID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)/restore", method: .put, body: nil)
    }

    func removeMember(organizationID: String, memberID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/users/\(memberID)/delete", method: .post, body: nil)
    }

    // MARK: - Sammlungen (roh — Namen kommen verschlüsselt vom SDK)

    /// Legt eine Sammlung an. `encryptedName` ist ein EncString, vom SDK mit dem
    /// Organisationsschlüssel verschlüsselt.
    func createCollection(organizationID: String, encryptedName: String, access: OrgCollectionDetails) async throws {
        let payload: [String: Any] = [
            "name": encryptedName,
            "externalId": NSNull(),
            "groups": access.groups.map(Self.accessPayload),
            "users": access.users.map(Self.accessPayload),
        ]
        _ = try await send("/api/organizations/\(organizationID)/collections", method: .post, body: payload)
    }

    func updateCollection(organizationID: String, collectionID: String, encryptedName: String, access: OrgCollectionDetails) async throws {
        let payload: [String: Any] = [
            "name": encryptedName,
            "externalId": NSNull(),
            "groups": access.groups.map(Self.accessPayload),
            "users": access.users.map(Self.accessPayload),
        ]
        _ = try await send("/api/organizations/\(organizationID)/collections/\(collectionID)", method: .put, body: payload)
    }

    func deleteCollection(organizationID: String, collectionID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/collections/\(collectionID)", method: .delete, body: nil)
    }

    /// Wer auf eine Sammlung zugreift — Mitglieder und Gruppen mit Rechten.
    func collectionDetails(organizationID: String, collectionID: String) async throws -> OrgCollectionDetails {
        let data = try await get("/api/organizations/\(organizationID)/collections/\(collectionID)/details")
        guard let node = try OrgParser.object(from: data) else { throw OrgError.invalidResponse }
        let users = node.nodes("users").compactMap(Self.access(from:))
        let groups = node.nodes("groups").compactMap(Self.access(from:))
        return OrgCollectionDetails(users: users, groups: groups)
    }

    // MARK: - Gruppen

    func groups(organizationID: String) async throws -> [OrgGroup] {
        let data = try await get("/api/organizations/\(organizationID)/groups")
        return try OrgParser.groups(from: data)
    }

    func createGroup(organizationID: String, name: String, collections: [OrgCollectionAccess]) async throws {
        let payload: [String: Any] = [
            "name": name,
            "accessAll": false,
            "collections": collections.map(Self.accessPayload),
            "users": [String](),
        ]
        _ = try await send("/api/organizations/\(organizationID)/groups", method: .post, body: payload)
    }

    func updateGroup(organizationID: String, groupID: String, name: String, collections: [OrgCollectionAccess]) async throws {
        let payload: [String: Any] = [
            "name": name,
            "accessAll": false,
            "collections": collections.map(Self.accessPayload),
        ]
        _ = try await send("/api/organizations/\(organizationID)/groups/\(groupID)", method: .put, body: payload)
    }

    func deleteGroup(organizationID: String, groupID: String) async throws {
        _ = try await send("/api/organizations/\(organizationID)/groups/\(groupID)", method: .delete, body: nil)
    }

    func groupMembers(organizationID: String, groupID: String) async throws -> [String] {
        let data = try await get("/api/organizations/\(organizationID)/groups/\(groupID)/users")
        let root = try JSONSerialization.jsonObject(with: data)
        if let ids = root as? [String] { return ids }
        return try OrgParser.list(from: data).compactMap { $0.string("id") }
    }

    func setGroupMembers(organizationID: String, groupID: String, memberIDs: [String]) async throws {
        _ = try await send("/api/organizations/\(organizationID)/groups/\(groupID)/users", method: .put, body: memberIDs)
    }

    // MARK: - Ereignisse

    func events(organizationID: String, days: Int = 30) async throws -> [OrgEvent] {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let end = formatter.string(from: Date())
        let start = formatter.string(from: Date().addingTimeInterval(-Double(days) * 86_400))
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        let safeStart = start.addingPercentEncoding(withAllowedCharacters: allowed) ?? start
        let safeEnd = end.addingPercentEncoding(withAllowedCharacters: allowed) ?? end
        let data = try await get("/api/organizations/\(organizationID)/events?start=\(safeStart)&end=\(safeEnd)")
        return try OrgParser.events(from: data)
    }

    // MARK: - Richtlinien

    func policies(organizationID: String) async throws -> [OrgPolicy] {
        let data = try await get("/api/organizations/\(organizationID)/policies")
        return try OrgParser.policies(from: data)
    }

    func setPolicy(organizationID: String, type: OrgPolicyType, enabled: Bool, dataJSON: String?) async throws {
        var payload: [String: Any] = ["type": type.rawValue, "enabled": enabled]
        if let dataJSON, let raw = dataJSON.data(using: .utf8), let parsed = try? JSONSerialization.jsonObject(with: raw) {
            payload["data"] = parsed
        } else {
            payload["data"] = NSNull()
        }
        _ = try await send("/api/organizations/\(organizationID)/policies/\(type.rawValue)", method: .put, body: payload)
    }

    // MARK: - Werkzeug

    private static func accessPayload(_ access: OrgCollectionAccess) -> [String: Any] {
        ["id": access.id, "readOnly": access.readOnly, "hidePasswords": access.hidePasswords, "manage": access.manage]
    }

    private static func access(from node: OrgParser.Node) -> OrgCollectionAccess? {
        guard let id = node.string("id") else { return nil }
        return OrgCollectionAccess(
            id: id,
            readOnly: node.bool("readOnly") ?? false,
            hidePasswords: node.bool("hidePasswords") ?? false,
            manage: node.bool("manage") ?? false
        )
    }

    private func get(_ path: String) async throws -> Data {
        try await send(path, method: .get, body: nil)
    }

    @discardableResult
    private func send(_ path: String, method: HTTPMethod, body: Any?) async throws -> Data {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else { throw OrgError.invalidResponse }
        var headers = ["Accept": "application/json"]
        var data: Data?
        if let body {
            headers["Content-Type"] = "application/json"
            data = try JSONSerialization.data(withJSONObject: body)
        }
        let request = HTTPRequest(url: url, method: method, headers: headers, body: data)
        let response: HTTPResponse
        do {
            response = try await http.send(request, shouldRetryIfUnauthorized: true)
        } catch {
            throw OrgError.transport(error.localizedDescription)
        }
        switch response.statusCode {
        case 200 ... 299:
            return response.body
        case 401:
            throw OrgError.unauthorized
        case 403:
            throw OrgError.forbidden
        case 404:
            throw OrgError.notFound
        default:
            throw OrgError.server(OrgParser.message(from: response.body) ?? "Der Server antwortete mit HTTP \(response.statusCode).")
        }
    }
}
