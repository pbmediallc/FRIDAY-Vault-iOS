// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import Combine
import Foundation

/// Zustand der Verwaltung EINER Organisation.
///
/// Zwei Quellen, bewusst getrennt:
/// * die Bitwarden-API (Mitglieder, Gruppen, Richtlinien, Zugriffe) — als Konto
///   angemeldet, im Regelfall mit dem Token des bw-Kerns, sonst mit dem persönlichen
///   API-Schlüssel;
/// * der bw-Kern (Sammlungen, Einträge, Bestätigen) — braucht den entsperrten Tresor,
///   weil dort die Schlüssel liegen.
///
/// Eine der beiden kann fehlen. Dann fehlt genau der Teil, und die Fläche sagt das —
/// statt eine leere Liste als „nichts vorhanden" auszugeben.
@MainActor
final class FridayOrgStore: ObservableObject {
    enum Phase: Equatable {
        /// Noch kein Versuch — die Fläche stößt `connect()` an.
        case connecting
        case opening
        case open
        case failed(String)
    }

    @Published private(set) var phase: Phase = .connecting
    @Published private(set) var members: [OrgMember] = []
    @Published private(set) var collections: [OrgCollection] = []
    @Published private(set) var groups: [OrgGroup] = []
    @Published private(set) var policies: [OrgPolicy] = []
    @Published private(set) var events: [OrgEvent] = []
    @Published private(set) var trash: [OrgItem] = []
    /// Eine E-Mail, die beim Öffnen sofort in den Einladen-Dialog soll — vom Konten-Reiter.
    @Published var pendingInviteEmail: String?
    @Published private(set) var eventsLoaded = false
    @Published private(set) var isBusy = false
    /// Wahr, wenn die Sammlungen nicht geladen werden konnten, weil der Tresor zu ist.
    @Published private(set) var collectionsBlocked = false
    @Published private(set) var organizationName: String
    @Published private(set) var billingEmail: String?
    @Published var selectedTab: OrgPanelTab = .collections
    @Published var vaultFilter: OrgVaultFilter = .overview
    /// Zugriffe je Sammlung, nachgeladen bei Bedarf (Kern-Aufruf je Sammlung).
    @Published private(set) var collectionDetails: [String: OrgCollectionDetails] = [:]
    /// Mitglieder je Gruppe, nachgeladen bei Bedarf.
    @Published private(set) var groupMembers: [String: [String]] = [:]
    @Published var notice: String?
    @Published var noticeIsWarning = false

    let host: String
    let organizationID: String
    /// Ob der Server Mail verschickt. `nil` heißt „unbekannt" — dann wird nichts behauptet.
    /// Beobachtbar, weil die Warnung zum fehlenden Mail-Versand daran haengt.
    @Published var mailEnabled: Bool?

    private let client: FridayOrgClient
    private let engine: any FridayOrgEngine

    init(
        host: String,
        organizationID: String,
        organizationName: String,
        engine: any FridayOrgEngine,
        client: FridayOrgClient,
        mailEnabled: Bool? = nil,
        pendingInviteEmail: String? = nil
    ) {
        self.host = host
        self.organizationID = organizationID
        self.organizationName = organizationName
        self.engine = engine
        self.mailEnabled = mailEnabled
        self.pendingInviteEmail = pendingInviteEmail
        self.client = client
        if pendingInviteEmail != nil { selectedTab = .members }
    }

    /// Holt die anstehende Einladung ab — genau einmal.
    func takePendingInvite() -> String? {
        defer { pendingInviteEmail = nil }
        return pendingInviteEmail
    }

    var vaultIsUnlocked: Bool { engine.vaultIsUnlocked }

    // MARK: - Öffnen

    /// Auf dem iPhone ist die App schon angemeldet; ihr Token hängt der HTTP-Dienst an.
    /// Öffnen heißt hier: laden — und ehrlich sagen, wenn der Server ablehnt.
    func connect() async {
        guard phase != .open, phase != .opening else { return }
        phase = .opening
        setBusy(true)
        defer { setBusy(false) }
        do {
            members = try await client.members(organizationID: organizationID)
        } catch {
            phase = .failed(OrgErrorText.readable(error))
            return
        }
        phase = .open
        await reloadAll()
    }

    // MARK: - Laden

    func reloadAll() async {
        await reloadSummary()
        await reloadMembers()
        await reloadCollections()
        await reloadGroups()
        await reloadPolicies()
        await reloadItems()
        await reloadTrash()
    }

    /// Name und Rechnungsadresse vom Server — still, weil nicht jede Fassung den
    /// Endpunkt bedient und die Fläche auch ohne ihn vollständig ist.
    func reloadSummary() async {
        guard phase == .open else { return }
        guard let summary = try? await client.organization(id: organizationID) else { return }
        organizationName = summary.name
        billingEmail = summary.billingEmail
    }

    func reloadMembers() async {
        guard phase == .open else { return }
        setBusy(true)
        defer { setBusy(false) }
        do {
            members = try await client.members(organizationID: organizationID)
        } catch {
            report(error)
        }
    }

    func reloadCollections() async {
        guard engine.vaultIsUnlocked else {
            collections = []
            collectionsBlocked = true
            return
        }
        setBusy(true)
        defer { setBusy(false) }
        do {
            collections = try await self.engine.orgCollections(organizationID: organizationID)
            collectionsBlocked = false
        } catch {
            collectionsBlocked = true
            setNotice(OrgErrorText.readable(error), warning: true)
        }
    }

    func reloadGroups() async {
        guard phase == .open else { return }
        do {
            groups = try await client.groups(organizationID: organizationID)
        } catch OrgError.notFound {
            // Gruppen kennt nicht jede Vaultwarden-Fassung. Das ist kein Fehler,
            // aber es wird auch nicht als „keine Gruppen" ausgegeben.
            groups = []
            setNotice("Dieser Server bietet keine Gruppenverwaltung an.", warning: false)
        } catch {
            report(error)
        }
    }

    /// Das Ereignisprotokoll — still bei 404, weil nicht jede Fassung es führt.
    func reloadEvents() async {
        guard phase == .open else { return }
        do {
            events = try await client.events(organizationID: organizationID)
            eventsLoaded = true
        } catch OrgError.notFound {
            events = []
            eventsLoaded = true
        } catch {
            report(error)
        }
    }

    func memberName(userID: String?) -> String? {
        guard let userID else { return nil }
        return members.first { $0.userID == userID }?.displayName
    }

    func reloadPolicies() async {
        guard phase == .open else { return }
        do {
            policies = try await client.policies(organizationID: organizationID)
        } catch OrgError.notFound {
            policies = []
            setNotice("Dieser Server bietet keine Richtlinien an.", warning: false)
        } catch {
            report(error)
        }
    }

    /// Die Einträge dieser Organisation, entschlüsselt vom SDK.
    @Published private(set) var items: [OrgItem] = []
    /// Einträge im persönlichen Tresor — Kandidaten für die Übernahme.
    @Published private(set) var personalItems: [OrgItem] = []

    func reloadItems() async {
        guard engine.vaultIsUnlocked else {
            items = []
            personalItems = []
            return
        }
        do {
            items = try await engine.organizationItems(organizationID: organizationID)
            personalItems = try await engine.personalItems()
        } catch {
            setNotice("Einträge: \(OrgErrorText.readable(error))", warning: true)
        }
    }

    func collectionName(_ id: String) -> String? {
        collections.first { $0.id == id }?.name
    }

    /// Die eigene Mitgliedschaft — bestimmt, was die Fläche als „Berechtigung" zeigt.
    var ownMembership: OrgMember? {
        let email = engine.accountEmail.lowercased()
        guard !email.isEmpty else { return nil }
        return members.first { $0.email.lowercased() == email }
    }

    /// Wie die Admin Console die Spalte „Berechtigung" füllt.
    func ownPermissionTitle(for collection: OrgCollection) -> String {
        guard let me = ownMembership else { return "—" }
        if me.seesEverything { return "Sammlung verwalten" }
        guard let access = me.collectionAccess.first(where: { $0.id == collection.id }) else { return "Kein Zugriff" }
        return access.permission == .canManage ? "Sammlung verwalten" : access.permission.title
    }

    func loadCollectionDetails(_ collection: OrgCollection) async {
        do {
            collectionDetails[collection.id] = try await self.engine.orgCollectionDetails(
                organizationID: organizationID,
                collectionID: collection.id
            )
        } catch {
            setNotice("Zugriff von „\(collection.name)“: \(OrgErrorText.readable(error))", warning: true)
        }
    }

    func loadGroupMembers(_ group: OrgGroup) async {
        guard phase == .open else { return }
        do {
            groupMembers[group.id] = try await client.groupMembers(organizationID: organizationID, groupID: group.id)
        } catch {
            setNotice("Mitglieder von „\(group.name)“: \(OrgErrorText.readable(error))", warning: true)
        }
    }

    // MARK: - Organisation schreiben

    func rename(to name: String, billingEmail email: String) async {
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !cleanName.isEmpty else {
            setNotice("Die Organisation braucht einen Namen.", warning: true)
            return
        }
        guard cleanEmail.contains("@"), !cleanEmail.hasPrefix("@"), !cleanEmail.hasSuffix("@") else {
            setNotice("Die Rechnungsadresse ist keine vollständige E-Mail-Adresse.", warning: true)
            return
        }
        await write("Umbenennen der Organisation") {
            try await self.client.updateOrganization(
                id: self.organizationID,
                name: cleanName,
                billingEmail: cleanEmail
            )
        } verify: {
            self.organizationName == cleanName
        } describeSuccess: {
            "Die Organisation heißt jetzt „\(cleanName)“."
        }
    }

    // MARK: - Mitglieder schreiben

    /// Lädt ein. Die Nachprüfung sucht das Konto in der neu geladenen Liste —
    /// eine Antwort ohne Fehler ist noch kein eingetragenes Mitglied.
    func invite(email: String, role: OrgMemberRole, collections: [OrgCollectionAccess] = [], groups: [String] = []) async {
        let clean = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard clean.contains("@"), !clean.hasPrefix("@"), !clean.hasSuffix("@") else {
            setNotice("Das ist keine vollständige E-Mail-Adresse.", warning: true)
            return
        }
        let access = role.seesEverything ? [] : collections
        await write("Einladung an \(clean)") {
            try await self.client.invite(
                organizationID: self.organizationID,
                emails: [clean],
                role: role,
                collections: access,
                groups: groups
            )
        } verify: {
            self.members.contains { $0.email.lowercased() == clean }
        } describeSuccess: {
            var text = "\(clean) ist als \(role.title) eingetragen"
            if !role.seesEverything {
                text += access.isEmpty
                    ? " — noch ohne Sammlung, sieht also noch nichts"
                    : " mit Zugriff auf \(access.count) Sammlung(en)"
            }
            if self.mailEnabled == false {
                return text + ". Dieser Server verschickt keine Mail — die Einladung erreicht niemanden von selbst."
            }
            if self.mailEnabled == nil {
                return text + ". Ob der Server die Einladung verschickt, ist nicht belegt."
            }
            return text + ". Die Einladung wurde verschickt."
        }
    }

    func resendInvite(_ member: OrgMember) async {
        await write("Erneute Einladung an \(member.email)") {
            try await self.client.resendInvite(
                organizationID: self.organizationID,
                memberID: member.id
            )
        } verify: {
            // Der Endpunkt ändert nichts am Zustand — hier gibt es nichts nachzuprüfen,
            // und das wird auch nicht so getan.
            true
        } describeSuccess: {
            self.mailEnabled == false
                ? "Der Server hat die Anfrage angenommen, verschickt aber keine Mail."
                : "Die Einladung wurde erneut verschickt."
        }
    }

    func setRole(_ role: OrgMemberRole, for member: OrgMember) async {
        await write("Rolle von \(member.displayName)") {
            try await self.client.updateMember(
                organizationID: self.organizationID,
                memberID: member.id,
                role: role,
                collections: member.collectionAccess,
                groups: member.groupIDs
            )
        } verify: {
            // Nur ein belegter Wert zählt. Fehlt das Feld, gilt der Schreibvorgang
            // als unbestätigt — nicht als erfolgreich.
            self.members.first { $0.id == member.id }?.roleRaw == role.rawValue
        } describeSuccess: {
            "\(member.displayName) ist jetzt \(role.title)."
        }
    }

    /// „Zugriff verwalten" aus der Admin Console: Rolle, Sammlungen und Gruppen in einem Zug.
    func setMemberAccess(_ member: OrgMember, role: OrgMemberRole, collections: [OrgCollectionAccess], groups: [String]) async {
        let access = role.seesEverything ? [] : collections
        let wantedAccess = Set(access)
        let wantedGroups = Set(groups)
        await write("Zugriff von \(member.displayName)") {
            try await self.client.updateMember(
                organizationID: self.organizationID,
                memberID: member.id,
                role: role,
                collections: access,
                groups: groups
            )
        } verify: {
            guard let current = self.members.first(where: { $0.id == member.id }) else { return false }
            guard current.roleRaw == role.rawValue else { return false }
            if !role.seesEverything, Set(current.collectionAccess) != wantedAccess { return false }
            return Set(current.groupIDs) == wantedGroups
        } describeSuccess: {
            role.seesEverything
                ? "\(member.displayName) ist \(role.title) und sieht alle Sammlungen."
                : "\(member.displayName): \(role.title), \(access.count) Sammlung(en), \(groups.count) Gruppe(n)."
        }
    }

    /// Bestätigt alle Mitglieder im Stand „angenommen" nacheinander — das, was nach einer
    /// Einladungswelle ansteht. Jede Bestätigung wird einzeln nachgeprüft.
    func confirmAllAccepted() async {
        let pending = members.filter { $0.status == .accepted }
        guard !pending.isEmpty else {
            setNotice("Niemand wartet auf Bestätigung.", warning: false)
            return
        }
        var done = 0
        for member in pending {
            await confirm(member)
            if members.first(where: { $0.id == member.id })?.status == .confirmed { done += 1 }
        }
        setNotice(
            "\(done) von \(pending.count) Mitglied(ern) bestätigt.",
            warning: done != pending.count
        )
    }

    /// Setzt, welche Sammlungen ein Mitglied sieht — mit welchen Rechten.
    func setCollectionAccess(_ access: [OrgCollectionAccess], for member: OrgMember) async {
        guard let role = member.role else {
            setNotice(
                "Die Rolle von \(member.displayName) ist nicht belegt — ohne sie wird nichts geschrieben, sonst käme eine erfundene Rolle mit.",
                warning: true
            )
            return
        }
        let wanted = Set(access)
        await write("Sammlungszugriff von \(member.displayName)") {
            try await self.client.updateMember(
                organizationID: self.organizationID,
                memberID: member.id,
                role: role,
                collections: access,
                groups: member.groupIDs
            )
        } verify: {
            guard let current = self.members.first(where: { $0.id == member.id }) else { return false }
            return Set(current.collectionAccess) == wanted
        } describeSuccess: {
            access.isEmpty
                ? "\(member.displayName) hat keinen Zugriff auf eine Sammlung mehr."
                : "\(member.displayName) hat Zugriff auf \(access.count) Sammlung(en)."
        }
    }

    func confirm(_ member: OrgMember) async {
        guard engine.vaultIsUnlocked else {
            setNotice(
                "Bestätigen verschlüsselt den Organisationsschlüssel für dieses Mitglied. Dafür muss der Tresor entsperrt sein.",
                warning: true
            )
            return
        }
        await write("Bestätigung von \(member.displayName)") {
            try await self.engine.syncEngine()
            try await self.engine.confirmOrgMember(
                organizationID: self.organizationID,
                memberID: member.id
            )
        } verify: {
            self.members.first { $0.id == member.id }?.statusRaw == OrgMemberStatus.confirmed.rawValue
        } describeSuccess: {
            "\(member.displayName) ist bestätigt."
        }
    }

    func revoke(_ member: OrgMember) async {
        await write("Entzug für \(member.displayName)") {
            try await self.client.revokeMember(
                organizationID: self.organizationID,
                memberID: member.id
            )
        } verify: {
            self.members.first { $0.id == member.id }?.statusRaw == OrgMemberStatus.revoked.rawValue
        } describeSuccess: {
            "\(member.displayName) hat keinen Zugriff mehr."
        }
    }

    func restore(_ member: OrgMember) async {
        await write("Wiederherstellung für \(member.displayName)") {
            try await self.client.restoreMember(
                organizationID: self.organizationID,
                memberID: member.id
            )
        } verify: {
            // Ein VERSCHWUNDENES Mitglied ist kein wiederhergestelltes. Ohne belegten
            // Stand gilt der Schreibvorgang als unbestaetigt.
            guard let status = self.members.first(where: { $0.id == member.id })?.statusRaw else {
                return false
            }
            return status != OrgMemberStatus.revoked.rawValue
        } describeSuccess: {
            "\(member.displayName) hat wieder Zugriff."
        }
    }

    func remove(_ member: OrgMember) async {
        await write("Entfernen von \(member.displayName)") {
            try await self.client.removeMember(
                organizationID: self.organizationID,
                memberID: member.id
            )
        } verify: {
            !self.members.contains { $0.id == member.id }
        } describeSuccess: {
            "\(member.displayName) wurde aus der Organisation entfernt."
        }
    }

    // MARK: - Sammlungen schreiben

    func createCollection(name: String, access: OrgCollectionDetails = OrgCollectionDetails()) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await write("Sammlung „\(clean)“") {
            try await self.engine.createOrgCollection(
                organizationID: self.organizationID,
                name: clean,
                access: access
            )
        } verify: {
            self.collections.contains { $0.name == clean }
        } describeSuccess: {
            let who = access.users.count + access.groups.count
            return who == 0
                ? "Sammlung „\(clean)“ angelegt — noch ohne Zugriff für Mitglieder."
                : "Sammlung „\(clean)“ angelegt, Zugriff für \(access.users.count) Mitglied(er) und \(access.groups.count) Gruppe(n)."
        }
    }

    /// „Zugriff verwalten" einer Sammlung: Mitglieder und Gruppen mit Rechten, nachgeprüft
    /// über den Kern. Bei Bedarf wird im selben Zug umbenannt.
    func setCollectionAccess(_ collection: OrgCollection, name: String, access: OrgCollectionDetails) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let wantedUsers = Set(access.users)
        let wantedGroups = Set(access.groups)
        await write("Zugriff auf „\(collection.name)“") {
            if !clean.isEmpty, clean != collection.name {
                try await self.engine.renameOrgCollection(organizationID: self.organizationID, collectionID: collection.id, name: clean)
            }
            try await self.engine.setOrgCollectionAccess(
                organizationID: self.organizationID,
                collectionID: collection.id,
                access: access
            )
            self.collectionDetails[collection.id] = try await self.engine.orgCollectionDetails(
                organizationID: self.organizationID,
                collectionID: collection.id
            )
        } verify: {
            guard let now = self.collectionDetails[collection.id] else { return false }
            if !clean.isEmpty, self.collections.first(where: { $0.id == collection.id })?.name != clean { return false }
            return Set(now.users) == wantedUsers && Set(now.groups) == wantedGroups
        } describeSuccess: {
            "„\(clean.isEmpty ? collection.name : clean)“: Zugriff für \(access.users.count) Mitglied(er) und \(access.groups.count) Gruppe(n) gesetzt."
        }
    }

    func renameCollection(_ collection: OrgCollection, to name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await write("Umbenennen von „\(collection.name)“") {
            try await self.engine.renameOrgCollection(
                organizationID: self.organizationID,
                collectionID: collection.id,
                name: clean
            )
        } verify: {
            self.collections.first { $0.id == collection.id }?.name == clean
        } describeSuccess: {
            "Sammlung heißt jetzt „\(clean)“."
        }
    }

    func deleteCollection(_ collection: OrgCollection) async {
        await write("Löschen von „\(collection.name)“") {
            try await self.engine.deleteOrgCollection(
                organizationID: self.organizationID,
                collectionID: collection.id
            )
        } verify: {
            !self.collections.contains { $0.id == collection.id }
        } describeSuccess: {
            "Sammlung „\(collection.name)“ gelöscht."
        }
    }

    // MARK: - Einträge schreiben

    /// Holt einen Eintrag aus dem persönlichen Tresor in die Organisation. Der Weg
    /// zurück existiert in Bitwarden nicht — der Eintrag gehört danach der Organisation.
    func adoptItem(_ item: OrgItem, collectionIDs: [String]) async {
        guard !collectionIDs.isEmpty else {
            setNotice("Ohne Sammlung kann ein Eintrag in der Organisation niemandem gehören.", warning: true)
            return
        }
        await write("Übernahme von „\(item.name)“") {
            try await self.engine.moveItemToOrganization(
                itemID: item.id,
                organizationID: self.organizationID,
                collectionIDs: collectionIDs
            )
        } verify: {
            self.items.contains { $0.id == item.id }
        } describeSuccess: {
            "„\(item.name)“ gehört jetzt der Organisation."
        }
    }

    func setItemCollections(_ collectionIDs: [String], for item: OrgItem) async {
        guard !collectionIDs.isEmpty else {
            setNotice("Ein Organisationseintrag braucht mindestens eine Sammlung.", warning: true)
            return
        }
        let wanted = Set(collectionIDs)
        await write("Sammlungen von „\(item.name)“") {
            try await self.engine.setItemCollections(itemID: item.id, collectionIDs: collectionIDs)
        } verify: {
            guard let current = self.items.first(where: { $0.id == item.id }) else { return false }
            return Set(current.collectionIDs) == wanted
        } describeSuccess: {
            "„\(item.name)“ liegt jetzt in \(collectionIDs.count) Sammlung(en)."
        }
    }

    func reloadTrash() async {
        guard engine.vaultIsUnlocked else {
            trash = []
            return
        }
        do {
            trash = try await self.engine.organizationTrashItems(organizationID: organizationID)
        } catch {
            setNotice("Papierkorb: \(OrgErrorText.readable(error))", warning: true)
        }
    }

    func restoreItem(_ item: OrgItem) async {
        await write("Wiederherstellen von „\(item.name)“") {
            try await self.engine.restoreItem(itemID: item.id)
            self.trash = try await self.engine.organizationTrashItems(organizationID: self.organizationID)
        } verify: {
            self.items.contains { $0.id == item.id } && !self.trash.contains { $0.id == item.id }
        } describeSuccess: {
            "„\(item.name)“ ist wieder in der Organisation."
        }
    }

    func trashItem(_ item: OrgItem) async {
        await write("Papierkorb für „\(item.name)“") {
            try await self.engine.trashItem(itemID: item.id)
        } verify: {
            !self.items.contains { $0.id == item.id }
        } describeSuccess: {
            "„\(item.name)“ liegt im Papierkorb."
        }
        await reloadTrash()
    }

    // MARK: - Gruppen schreiben

    func createGroup(name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await write("Gruppe „\(clean)“") {
            try await self.client.createGroup(
                organizationID: self.organizationID,
                name: clean,
                collections: []
            )
        } verify: {
            self.groups.contains { $0.name == clean }
        } describeSuccess: {
            "Gruppe „\(clean)“ angelegt."
        }
    }

    func renameGroup(_ group: OrgGroup, to name: String) async {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        await write("Umbenennen von „\(group.name)“") {
            try await self.client.updateGroup(
                organizationID: self.organizationID,
                groupID: group.id,
                name: clean,
                collections: group.collectionIDs.map { OrgCollectionAccess(id: $0) }
            )
        } verify: {
            self.groups.first { $0.id == group.id }?.name == clean
        } describeSuccess: {
            "Gruppe heißt jetzt „\(clean)“."
        }
    }

    func setGroupMembers(_ group: OrgGroup, memberIDs: [String]) async {
        let wanted = Set(memberIDs)
        await write("Mitglieder von „\(group.name)“") {
            try await self.client.setGroupMembers(
                organizationID: self.organizationID,
                groupID: group.id,
                memberIDs: memberIDs
            )
            self.groupMembers[group.id] = try await self.client.groupMembers(
                organizationID: self.organizationID,
                groupID: group.id
            )
        } verify: {
            Set(self.groupMembers[group.id] ?? []) == wanted
        } describeSuccess: {
            "„\(group.name)“ hat \(memberIDs.count) Mitglied(er)."
        }
    }

    func setGroupCollections(_ group: OrgGroup, collections: [OrgCollectionAccess]) async {
        let wanted = Set(collections.map(\.id))
        await write("Sammlungen von „\(group.name)“") {
            try await self.client.updateGroup(
                organizationID: self.organizationID,
                groupID: group.id,
                name: group.name,
                collections: collections
            )
        } verify: {
            Set(self.groups.first { $0.id == group.id }?.collectionIDs ?? []) == wanted
        } describeSuccess: {
            "„\(group.name)“ hat Zugriff auf \(collections.count) Sammlung(en)."
        }
    }

    func deleteGroup(_ group: OrgGroup) async {
        await write("Löschen von „\(group.name)“") {
            try await self.client.deleteGroup(
                organizationID: self.organizationID,
                groupID: group.id
            )
        } verify: {
            !self.groups.contains { $0.id == group.id }
        } describeSuccess: {
            "Gruppe „\(group.name)“ gelöscht."
        }
    }

    // MARK: - Richtlinien schreiben

    func setPolicy(_ type: OrgPolicyType, enabled: Bool) async {
        let existing = policies.first { $0.typeRaw == type.rawValue }
        await write("Richtlinie „\(type.title)“") {
            try await self.client.setPolicy(
                organizationID: self.organizationID,
                type: type,
                enabled: enabled,
                dataJSON: existing?.dataJSON
            )
        } verify: {
            self.policies.first { $0.typeRaw == type.rawValue }?.enabled == enabled
        } describeSuccess: {
            enabled ? "„\(type.title)“ ist aktiv." : "„\(type.title)“ ist aus."
        }
    }

    // MARK: - Schreiben mit Nachprüfung

    /// Führt einen Schreibvorgang aus, lädt danach neu und prüft die WIRKUNG.
    ///
    /// Eine Antwort ohne Fehler ist kein Beweis. Wenn die Nachprüfung den Zustand
    /// nicht bestätigt, sagt die Fläche genau das — sie meldet nicht Vollzug.
    private func write(
        _ label: String,
        action: @escaping () async throws -> Void,
        verify: @escaping () -> Bool,
        describeSuccess: @escaping () -> String
    ) async {
        guard !isBusy else { return }
        setBusy(true)
        defer { setBusy(false) }

        do {
            try await action()
        } catch {
            setNotice("\(label): \(OrgErrorText.readable(error))", warning: true)
            return
        }

        await reloadSummary()
        await reloadMembers()
        await reloadCollections()
        await reloadGroups()
        await reloadPolicies()
        await reloadItems()

        if verify() {
            setNotice(describeSuccess(), warning: false)
        } else {
            setNotice(
                "\(label): Der Server hat die Anfrage angenommen, aber die Wirkung ist nicht nachweisbar. Bitte prüfen.",
                warning: true
            )
        }
    }

    // MARK: - Werkzeug

    private func setBusy(_ value: Bool) { isBusy = value }

    /// Eine abgelehnte oder verlorene Sitzung ist kein Hinweis am Rand — sie beendet die
    /// Fläche. Alles andere bleibt ein Hinweis, die Fläche bleibt offen.
    private func report(_ error: Error) {
        if let orgError = error as? OrgError, orgError == .unauthorized || orgError == .notAuthenticated {
            phase = .failed(OrgErrorText.readable(error))
            return
        }
        setNotice(OrgErrorText.readable(error), warning: true)
    }

    func setNotice(_ message: String?, warning: Bool) {
        notice = message
        noticeIsWarning = warning
    }
}
