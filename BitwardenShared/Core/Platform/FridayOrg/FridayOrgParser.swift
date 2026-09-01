// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import Foundation

/// Liest die Antworten der Bitwarden-API.
///
/// Bewusst nachsichtig bei der Schreibweise der Schlüssel: Vaultwarden hat über die
/// Fassungen zwischen `Data`/`data`, `Type`/`type` und `UserId`/`userId` gewechselt.
/// Wer auf eine Schreibweise wettet, steht bei der nächsten Fassung vor einer leeren
/// Liste — und hält sie für „keine Mitglieder".
///
/// Bewusst NICHT nachsichtig bei fehlenden Werten: was der Server nicht schickt,
/// bleibt `nil` und wird nicht erfunden.
enum OrgParser {
    // MARK: - Nachsichtiger Zugriff

    /// Ein JSON-Objekt mit Schlüsselsuche ohne Rücksicht auf Groß-/Kleinschreibung.
    /// Sucht NUR auf der eigenen Ebene — nie in der Tiefe. Ein tiefensuchender Leser
    /// findet irgendwann irgendein `id` und hält es für seines.
    struct Node {
        let fields: [String: Any]

        init?(_ any: Any?) {
            guard let dictionary = any as? [String: Any] else { return nil }
            fields = dictionary
        }

        func value(_ key: String) -> Any? {
            if let direct = fields[key] { return direct }
            let needle = key.lowercased()
            for (name, value) in fields where name.lowercased() == needle { return value }
            return nil
        }

        func string(_ key: String) -> String? {
            switch value(key) {
            case let text as String: text.isEmpty ? nil : text
            case let number as NSNumber: number.stringValue
            default: nil
            }
        }

        func int(_ key: String) -> Int? {
            switch value(key) {
            case let number as NSNumber: number.intValue
            case let text as String: Int(text)
            default: nil
            }
        }

        func bool(_ key: String) -> Bool? {
            switch value(key) {
            case let flag as Bool: flag
            case let number as NSNumber: number.boolValue
            case let text as String:
                ["true", "1", "yes"].contains(text.lowercased()) ? true
                    : (["false", "0", "no"].contains(text.lowercased()) ? false : nil)
            default: nil
            }
        }

        func array(_ key: String) -> [Any] { value(key) as? [Any] ?? [] }

        func nodes(_ key: String) -> [Node] { array(key).compactMap(Node.init) }
    }

    /// Die Nutzlast einer Listenantwort. Bitwarden verpackt Listen in `{"data": [...]}`,
    /// ältere Fassungen in `{"Data": [...]}`, manche Endpunkte antworten mit einer
    /// nackten Liste. Alle drei Formen kommen vor.
    static func list(from data: Data) throws -> [Node] {
        let root = try JSONSerialization.jsonObject(with: data)
        if let array = root as? [Any] { return array.compactMap(Node.init) }
        guard let node = Node(root) else { return [] }
        let payload = node.array("data")
        if !payload.isEmpty { return payload.compactMap(Node.init) }
        // Eine leere `data`-Liste ist eine Antwort, kein Fehler.
        if node.value("data") != nil { return [] }
        return []
    }

    static func object(from data: Data) throws -> Node? {
        Node(try JSONSerialization.jsonObject(with: data))
    }

    // MARK: - Mitglieder

    static func members(from data: Data) throws -> [OrgMember] {
        try list(from: data).compactMap(member(from:))
    }

    static func member(from node: Node) -> OrgMember? {
        guard let id = node.string("id") else { return nil }
        // Ohne E-Mail ist die Zeile für Patrick wertlos — dann lieber nicht zeigen.
        guard let email = node.string("email") else { return nil }

        let collections: [OrgCollectionAccess] = {
            let raw = node.array("collections")
            let asStrings = raw.compactMap { $0 as? String }
            if !asStrings.isEmpty { return asStrings.map { OrgCollectionAccess(id: $0) } }
            return raw.compactMap { element in
                guard let entry = Node(element), let id = entry.string("id") else { return nil }
                return OrgCollectionAccess(
                    id: id,
                    readOnly: entry.bool("readOnly") ?? false,
                    hidePasswords: entry.bool("hidePasswords") ?? false,
                    manage: entry.bool("manage") ?? false
                )
            }
        }()
        let groups: [String] = {
            let raw = node.array("groups")
            let asStrings = raw.compactMap { $0 as? String }
            if !asStrings.isEmpty { return asStrings }
            return raw.compactMap { Node($0)?.string("id") }
        }()

        return OrgMember(
            id: id,
            userID: node.string("userId") ?? node.string("userID"),
            email: email,
            name: node.string("name"),
            roleRaw: node.int("type"),
            statusRaw: node.int("status"),
            twoFactorEnabled: node.bool("twoFactorEnabled"),
            collectionAccess: collections,
            groupIDs: groups,
            accessAll: node.bool("accessAll")
        )
    }

    // MARK: - Konto und Organisation

    static func profile(from data: Data) throws -> OrgProfile? {
        guard let node = try object(from: data), let id = node.string("id"), let email = node.string("email") else {
            return nil
        }
        return OrgProfile(id: id, email: email, name: node.string("name"))
    }

    /// `GET /api/users/{id}/public-key` liefert den Schlüssel als Base64 eines
    /// SubjectPublicKeyInfo. Kommt nichts Dekodierbares, gibt es keinen Schlüssel —
    /// und damit auch keine Organisation.
    static func publicKey(from data: Data) throws -> Data? {
        guard let node = try object(from: data), let encoded = node.string("publicKey") else { return nil }
        return Data(base64Encoded: encoded)
    }

    static func organization(from data: Data) throws -> OrgSummary? {
        guard let node = try object(from: data), let id = node.string("id"), let name = node.string("name") else {
            return nil
        }
        return OrgSummary(id: id, name: name, billingEmail: node.string("billingEmail"))
    }

    // MARK: - Gruppen

    static func groups(from data: Data) throws -> [OrgGroup] {
        try list(from: data).compactMap { node in
            guard let id = node.string("id"), let name = node.string("name") else { return nil }
            let collections: [String] = {
                let raw = node.array("collections")
                let asStrings = raw.compactMap { $0 as? String }
                if !asStrings.isEmpty { return asStrings }
                return raw.compactMap { Node($0)?.string("id") }
            }()
            return OrgGroup(
                id: id,
                name: name,
                externalID: node.string("externalId"),
                collectionIDs: collections
            )
        }
    }

    // MARK: - Richtlinien

    static func policies(from data: Data) throws -> [OrgPolicy] {
        try list(from: data).compactMap { node in
            guard let type = node.int("type") else { return nil }
            let enabled = node.bool("enabled") ?? false
            var dataJSON: String?
            if let payload = node.value("data"), !(payload is NSNull) {
                dataJSON = (try? JSONSerialization.data(withJSONObject: payload))
                    .map { String(decoding: $0, as: UTF8.self) }
            }
            return OrgPolicy(typeRaw: type, enabled: enabled, dataJSON: dataJSON)
        }
    }

    // MARK: - Ereignisse

    static func events(from data: Data) throws -> [OrgEvent] {
        try list(from: data).enumerated().compactMap { index, node in
            guard let type = node.int("type"), let date = node.string("date") else { return nil }
            return OrgEvent(
                id: "\(date)-\(type)-\(index)",
                typeRaw: type,
                date: date,
                actingUserID: node.string("actingUserId"),
                userID: node.string("userId"),
                cipherID: node.string("cipherId"),
                collectionID: node.string("collectionId"),
                groupID: node.string("groupId"),
                memberID: node.string("organizationUserId")
            )
        }
    }

    // MARK: - Zugriffe auf eine Sammlung

    static func collectionAccess(from data: Data) throws -> [OrgCollectionAccess] {
        try list(from: data).compactMap { node in
            guard let id = node.string("id") else { return nil }
            return OrgCollectionAccess(
                id: id,
                readOnly: node.bool("readOnly") ?? false,
                hidePasswords: node.bool("hidePasswords") ?? false,
                manage: node.bool("manage") ?? false
            )
        }
    }

    // MARK: - Zugangstoken

    struct Token: Sendable, Equatable {
        let accessToken: String
        let expiresIn: TimeInterval
    }

    static func token(from data: Data) throws -> Token? {
        guard let node = try object(from: data),
              let value = node.string("access_token") else { return nil }
        let seconds = node.int("expires_in").map(TimeInterval.init) ?? 3600
        return Token(accessToken: value, expiresIn: seconds)
    }

    /// Holt die Fehlermeldung aus einer Antwort — Bitwarden verteilt sie auf mehrere
    /// Stellen, je nachdem welche Schicht abgelehnt hat.
    static func message(from data: Data) -> String? {
        guard let node = try? object(from: data) else { return nil }
        if let direct = node.string("message") { return direct }
        if let description = node.string("error_description") { return description }
        if let error = node.string("error") { return error }
        if let model = Node(node.value("errorModel")), let text = model.string("message") {
            return text
        }
        if let validation = Node(node.value("validationErrors")) {
            let all = validation.fields.values
                .compactMap { ($0 as? [Any])?.compactMap { $0 as? String } }
                .flatMap { $0 }
            if !all.isEmpty { return all.joined(separator: " ") }
        }
        return nil
    }
}
