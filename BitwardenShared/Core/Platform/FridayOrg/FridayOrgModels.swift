// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import BitwardenSdk
import Foundation

// MARK: - Rollen

/// Die Rolle eines Mitglieds in der Organisation.
/// Zahlen sind Bitwardens `OrganizationUserType` — sie sind Vertrag, nicht Geschmack.
enum OrgMemberRole: Int, CaseIterable, Identifiable, Sendable {
    case owner = 0
    case admin = 1
    case user = 2
    case manager = 3
    case custom = 4

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .owner: "Eigentümer"
        case .admin: "Administrator"
        case .user: "Mitglied"
        case .manager: "Verwalter"
        case .custom: "Eigene Rechte"
        }
    }

    /// Rollen, die die Fläche zur Auswahl anbietet — in der Reihenfolge der Admin Console.
    /// `custom` wird angezeigt, aber nicht vergeben — dafür bräuchte es die Rechtematrix.
    static var assignable: [OrgMemberRole] { [.user, .manager, .admin, .owner] }

    /// Die Beschreibung, wie sie im Einladen-Dialog des Web-Tresors steht.
    var explanation: String {
        switch self {
        case .user: "Kann auf zugewiesene Sammlungen zugreifen und sie bearbeiten."
        case .manager: "Wie Mitglied, kann zusätzlich zugewiesene Sammlungen verwalten."
        case .admin: "Kann auf alle Sammlungen, Mitglieder, Gruppen und Berichte zugreifen und sie verwalten."
        case .owner: "Kann jeden Aspekt der Organisation verwalten — auch Einstellungen und Löschen."
        case .custom: "Eigene Rechtematrix — hier nur angezeigt, nicht vergeben."
        }
    }

    /// Eigentümer und Administratoren sehen jede Sammlung — eine Zuordnung
    /// beschränkt sie nicht.
    var seesEverything: Bool { self == .owner || self == .admin }
}

/// Der Stand eines Mitglieds. Bitwardens `OrganizationUserStatusType`.
enum OrgMemberStatus: Int, Sendable {
    case revoked = -1
    case invited = 0
    case accepted = 1
    case confirmed = 2

    var title: String {
        switch self {
        case .revoked: "Entzogen"
        case .invited: "Eingeladen"
        case .accepted: "Angenommen"
        case .confirmed: "Bestätigt"
        }
    }

    /// Nur ein Mitglied im Stand „angenommen" kann bestätigt werden —
    /// erst dann liegt sein öffentlicher Schlüssel auf dem Server.
    var awaitsConfirmation: Bool { self == .accepted }
}

// MARK: - Mitglied

/// Ein Mitglied, wie `GET /api/organizations/{id}/users` es liefert.
/// Fehlende Felder bleiben `nil` — die Fläche zeigt dann „unbekannt",
/// statt einen Zustand zu behaupten.
struct OrgMember: Identifiable, Hashable, Sendable {
    let id: String
    let userID: String?
    let email: String
    let name: String?
    let roleRaw: Int?
    let statusRaw: Int?
    let twoFactorEnabled: Bool?
    /// Der gemeldete Zugriff je Sammlung, mit Rechten. Wer nur die Kennungen
    /// weiterreicht, wirft beim nächsten Schreiben die Rechte weg.
    let collectionAccess: [OrgCollectionAccess]
    let groupIDs: [String]
    /// Ältere Fassungen melden `accessAll`. `nil` heißt „nicht gemeldet".
    let accessAll: Bool?

    init(
        id: String,
        userID: String?,
        email: String,
        name: String?,
        roleRaw: Int?,
        statusRaw: Int?,
        twoFactorEnabled: Bool?,
        collectionAccess: [OrgCollectionAccess] = [],
        groupIDs: [String] = [],
        accessAll: Bool? = nil
    ) {
        self.id = id
        self.userID = userID
        self.email = email
        self.name = name
        self.roleRaw = roleRaw
        self.statusRaw = statusRaw
        self.twoFactorEnabled = twoFactorEnabled
        self.collectionAccess = collectionAccess
        self.groupIDs = groupIDs
        self.accessAll = accessAll
    }

    var collectionIDs: [String] { collectionAccess.map(\.id) }
    var role: OrgMemberRole? { roleRaw.flatMap(OrgMemberRole.init(rawValue:)) }
    var status: OrgMemberStatus? { statusRaw.flatMap(OrgMemberStatus.init(rawValue:)) }

    var displayName: String {
        if let name, !name.trimmingCharacters(in: .whitespaces).isEmpty { return name }
        return email
    }

    /// Ob Rolle und Stand überhaupt belegt sind. Für die NACHPRÜFUNG eines
    /// Schreibvorgangs darf eine Vorgabe niemals einspringen.
    var isCertain: Bool { roleRaw != nil && statusRaw != nil }

    /// Ob die Sammlungsliste dieses Mitglied überhaupt beschränkt.
    var seesEverything: Bool { role?.seesEverything == true || accessAll == true }
}

// MARK: - Sammlung

/// Eine Sammlung. Der Name kommt entschlüsselt aus dem bw-Kern —
/// über die rohe API käme nur Chiffre.
struct OrgCollection: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let organizationID: String
    let externalID: String?
    /// `true`, wenn der Name nicht entschlüsselt werden konnte.
    let nameIsCipher: Bool

    init(
        id: String,
        name: String,
        organizationID: String,
        externalID: String? = nil,
        nameIsCipher: Bool = false
    ) {
        self.id = id
        self.name = name
        self.organizationID = organizationID
        self.externalID = externalID
        self.nameIsCipher = nameIsCipher
    }
}

/// Die fünf Berechtigungsstufen der Admin Console — wörtlich wie im Web-Tresor.
/// Dahinter stehen Bitwardens drei Schalter `readOnly`, `hidePasswords`, `manage`.
enum OrgPermission: Int, CaseIterable, Identifiable, Sendable {
    case canView
    case canViewExceptPasswords
    case canEdit
    case canEditExceptPasswords
    case canManage

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .canView: "Kann anzeigen"
        case .canViewExceptPasswords: "Kann anzeigen, außer Passwörter"
        case .canEdit: "Kann bearbeiten"
        case .canEditExceptPasswords: "Kann bearbeiten, außer Passwörter"
        case .canManage: "Kann verwalten"
        }
    }

    var readOnly: Bool { self == .canView || self == .canViewExceptPasswords }
    var hidePasswords: Bool { self == .canViewExceptPasswords || self == .canEditExceptPasswords }
    var manage: Bool { self == .canManage }

    init(readOnly: Bool, hidePasswords: Bool, manage: Bool) {
        if manage { self = .canManage; return }
        switch (readOnly, hidePasswords) {
        case (true, false): self = .canView
        case (true, true): self = .canViewExceptPasswords
        case (false, false): self = .canEdit
        case (false, true): self = .canEditExceptPasswords
        }
    }
}

/// Der Zugriff eines Mitglieds oder einer Gruppe auf eine Sammlung.
struct OrgCollectionAccess: Hashable, Sendable, Codable, Identifiable {
    let id: String
    var readOnly: Bool
    var hidePasswords: Bool
    var manage: Bool

    init(id: String, readOnly: Bool = false, hidePasswords: Bool = false, manage: Bool = false) {
        self.id = id
        self.readOnly = readOnly
        self.hidePasswords = hidePasswords
        self.manage = manage
    }

    init(id: String, permission: OrgPermission) {
        self.init(id: id, readOnly: permission.readOnly, hidePasswords: permission.hidePasswords, manage: permission.manage)
    }

    var permission: OrgPermission {
        get { OrgPermission(readOnly: readOnly, hidePasswords: hidePasswords, manage: manage) }
        set {
            readOnly = newValue.readOnly
            hidePasswords = newValue.hidePasswords
            manage = newValue.manage
        }
    }
}

/// Wer auf eine Sammlung zugreifen darf — Mitglieder (nach Mitglieds-Kennung) und Gruppen.
/// Kommt aus dem bw-Kern (`get org-collection`), der beides mitliefert.
struct OrgCollectionDetails: Hashable, Sendable {
    var users: [OrgCollectionAccess]
    var groups: [OrgCollectionAccess]

    init(users: [OrgCollectionAccess] = [], groups: [OrgCollectionAccess] = []) {
        self.users = users
        self.groups = groups
    }
}

// MARK: - Gruppe

struct OrgGroup: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let externalID: String?
    let collectionIDs: [String]
}

// MARK: - Richtlinie

/// Bitwardens `PolicyType`. Vaultwarden kennt nicht jede davon —
/// unbekannte kommen als `nil` zurück und werden nicht angezeigt.
enum OrgPolicyType: Int, CaseIterable, Identifiable, Sendable {
    case twoFactorAuthentication = 0
    case masterPassword = 1
    case passwordGenerator = 2
    case singleOrg = 3
    case requireSSO = 4
    case personalOwnership = 5
    case disableSend = 6
    case sendOptions = 7
    case resetPassword = 8
    case maximumVaultTimeout = 9
    case disablePersonalVaultExport = 10

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .twoFactorAuthentication: "Zwei-Faktor verlangen"
        case .masterPassword: "Master-Passwort-Regeln"
        case .passwordGenerator: "Generator-Regeln"
        case .singleOrg: "Nur diese Organisation"
        case .requireSSO: "Anmeldung über SSO"
        case .personalOwnership: "Privater Tresor gesperrt"
        case .disableSend: "Send abschalten"
        case .sendOptions: "Send-Regeln"
        case .resetPassword: "Passwort-Rücksetzung"
        case .maximumVaultTimeout: "Längste Tresor-Sperrzeit"
        case .disablePersonalVaultExport: "Export sperren"
        }
    }

    var explanation: String {
        switch self {
        case .twoFactorAuthentication:
            "Mitglieder ohne zweiten Faktor werden aus der Organisation entfernt."
        case .masterPassword: "Setzt Mindestanforderungen an das Master-Passwort."
        case .passwordGenerator: "Setzt Vorgaben für den Passwortgenerator."
        case .singleOrg: "Mitglieder dürfen keiner weiteren Organisation angehören."
        case .requireSSO: "Anmeldung nur über den Identitätsanbieter."
        case .personalOwnership: "Neue Einträge landen immer in der Organisation."
        case .disableSend: "Mitglieder können kein Send erstellen."
        case .sendOptions: "Schränkt die Möglichkeiten beim Send ein."
        case .resetPassword: "Administratoren dürfen Master-Passwörter zurücksetzen."
        case .maximumVaultTimeout: "Erzwingt eine höchste Sperrzeit."
        case .disablePersonalVaultExport: "Mitglieder dürfen den Tresor nicht ausleiten."
        }
    }
}

struct OrgPolicy: Identifiable, Hashable, Sendable {
    let typeRaw: Int
    let enabled: Bool
    /// Die Feineinstellung der Richtlinie, roh belassen — die Fläche zeigt
    /// bisher nur an/aus und fasst sie nicht an.
    let dataJSON: String?

    var id: Int { typeRaw }
    var type: OrgPolicyType? { OrgPolicyType(rawValue: typeRaw) }
}

// MARK: - Konto und Organisation

/// Das eigene Konto, wie `GET /api/accounts/profile` es meldet.
struct OrgProfile: Sendable, Equatable {
    let id: String
    let email: String
    let name: String?
}

/// Eine Organisation als Ganzes, wie `GET /api/organizations/{id}` sie meldet.
struct OrgSummary: Sendable, Equatable, Identifiable {
    let id: String
    let name: String
    let billingEmail: String?
}

/// Woher der Zugang zur Bitwarden-API kommt.
enum OrgAuthSource: Sendable, Equatable {
    case none
    /// Das Token, das der bw-Kern nach der Anmeldung des Tresors hält.
    case vaultSession
    /// Ein persönlicher API-Schlüssel aus der Keychain.
    case apiKey

    var title: String {
        switch self {
        case .none: "nicht verbunden"
        case .vaultSession: "über den Tresor-Kern"
        case .apiKey: "über den API-Schlüssel"
        }
    }
}

// MARK: - Ereignis

/// Ein Eintrag im Ereignisprotokoll der Organisation (`GET /api/organizations/{id}/events`).
/// Vaultwarden führt es nur, wenn `ORG_EVENTS_ENABLED` gesetzt ist — sonst kommt eine leere Liste.
struct OrgEvent: Identifiable, Hashable, Sendable {
    let id: String
    let typeRaw: Int
    let date: String
    let actingUserID: String?
    let userID: String?
    let cipherID: String?
    let collectionID: String?
    let groupID: String?
    let memberID: String?

    /// Bitwardens `EventType`, in Worten.
    var title: String {
        switch typeRaw {
        case 1000: "Anmeldung"
        case 1001: "Master-Passwort geändert"
        case 1002: "Zwei-Faktor aktiviert"
        case 1003: "Zwei-Faktor deaktiviert"
        case 1005: "Passwort-Rücksetzung"
        case 1007: "Tresor exportiert"
        case 1100: "Eintrag angelegt"
        case 1101: "Eintrag geändert"
        case 1102: "Eintrag gelöscht"
        case 1103: "Anhang hinzugefügt"
        case 1104: "Anhang gelöscht"
        case 1105: "Eintrag in Organisation übernommen"
        case 1106: "Sammlungen des Eintrags geändert"
        case 1107: "Eintrag angesehen"
        case 1108: "Passwort angesehen"
        case 1109: "Verstecktes Feld angesehen"
        case 1110: "Karten-Code angesehen"
        case 1111: "Passwort kopiert"
        case 1112: "Verstecktes Feld kopiert"
        case 1113: "Karten-Code kopiert"
        case 1114: "Automatisch ausgefüllt"
        case 1115: "Eintrag in den Papierkorb"
        case 1116: "Eintrag wiederhergestellt"
        case 1300: "Sammlung angelegt"
        case 1301: "Sammlung geändert"
        case 1302: "Sammlung gelöscht"
        case 1400: "Gruppe angelegt"
        case 1401: "Gruppe geändert"
        case 1402: "Gruppe gelöscht"
        case 1500: "Mitglied eingeladen"
        case 1501: "Mitglied bestätigt"
        case 1502: "Mitglied geändert"
        case 1503: "Mitglied entfernt"
        case 1504: "Gruppen des Mitglieds geändert"
        case 1508: "Zugriff entzogen"
        case 1509: "Zugriff wiederhergestellt"
        case 1600: "Organisation geändert"
        case 1700: "Richtlinie geändert"
        default: "Ereignis \(typeRaw)"
        }
    }
}

// MARK: - Reiter

/// Die Seitenleiste der Admin Console, in ihrer Reihenfolge.
enum OrgPanelTab: String, CaseIterable, Identifiable, Sendable {
    case collections
    case members
    case groups
    case reports
    case policies
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .collections: "Sammlungen"
        case .members: "Mitglieder"
        case .groups: "Gruppen"
        case .reports: "Berichte"
        case .policies: "Richtlinien"
        case .settings: "Einstellungen"
        }
    }

    var symbol: String {
        switch self {
        case .collections: "archivebox"
        case .members: "person"
        case .groups: "person.3"
        case .reports: "list.bullet.rectangle"
        case .policies: "checkmark.shield"
        case .settings: "gearshape"
        }
    }
}

/// Was die Sammlungs-Ansicht gerade zeigt — der Filter links, wie im Web-Tresor.
enum OrgVaultFilter: Hashable, Sendable {
    /// Die Übersicht aller Sammlungen (Tabelle Name · Berechtigung).
    case overview
    case allItems
    case type(CipherType)
    case collection(String)
    case trash
}

// MARK: - Fehlertext

enum OrgErrorText {
    /// Eine Meldung, die Patrick lesen kann — ohne Typnamen, ohne Stack.
    static func readable(_ error: Error) -> String {
        if let orgError = error as? OrgError { return orgError.errorDescription ?? "Unbekannter Fehler." }
        if let engineError = error as? OrgEngineError { return engineError.errorDescription ?? "Unbekannter Fehler." }
        if let cryptoError = error as? OrgCryptoError { return cryptoError.errorDescription ?? "Unbekannter Fehler." }
        return error.localizedDescription
    }
}

/// Ein Eintrag der Organisation, so wie die Fläche ihn braucht — entschlüsselt vom SDK.
struct OrgItem: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let subtitle: String
    let organizationID: String?
    let collectionIDs: [String]
    let type: CipherType
    let deletedDate: Date?
}

enum OrgEngineError: LocalizedError, Equatable, Sendable {
    case vaultLocked
    case invalidName
    case noCollection
    case noOrganizationKey
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case .vaultLocked:
            "Der Tresor ist gesperrt. Ohne entsperrten Tresor gibt es keine Schlüssel für Sammlungen."
        case .invalidName:
            "Der Name darf nicht leer sein."
        case .noCollection:
            "Ein Organisationseintrag braucht mindestens eine Sammlung."
        case .noOrganizationKey:
            "Der Organisationsschlüssel ließ sich nicht entschlüsseln — ohne ihn kein Bestätigen."
        case let .unsupported(what):
            "\(what) ist in dieser App nicht möglich."
        }
    }
}
