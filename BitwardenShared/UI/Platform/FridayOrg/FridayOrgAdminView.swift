// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import BitwardenKit
import BitwardenSdk
import Combine
import SwiftUI

// MARK: - Einhängung

/// Besitzt Organisationen, Kern und Store — die Fläche rendert nur.
@MainActor
final class FridayOrgHostModel: ObservableObject {
    typealias Services = FridayOrgVaultEngine.Services & HasAPIService & HasEnvironmentService

    @Published private(set) var organizations: [Organization] = []
    @Published private(set) var loading = true
    @Published private(set) var store: FridayOrgStore?
    @Published private(set) var host = ""

    private let services: Services

    init(services: Services) {
        self.services = services
        host = services.environmentService.baseURL.host ?? services.environmentService.baseURL.absoluteString
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            for try await organizations in try await services.vaultRepository.organizationsPublisher() {
                self.organizations = organizations
                    .filter(\.enabled)
                    .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
                break
            }
        } catch {
            organizations = []
        }
    }

    func open(_ organization: Organization) {
        let client = FridayOrgClient(http: services.apiService.apiService, baseURL: services.environmentService.baseURL)
        let engine = FridayOrgVaultEngine(services: services, client: client)
        let store = FridayOrgStore(
            host: host,
            organizationID: organization.id,
            organizationName: organization.name,
            engine: engine,
            client: client
        )
        self.store = store
        Task {
            await engine.prepare()
            await store.connect()
        }
    }

    func close() {
        store = nil
    }
}

/// Der Einstieg aus den Einstellungen: Organisationen des Kontos, dann die Admin Console.
struct FridayOrgHostView: View {
    @StateObject private var model: FridayOrgHostModel

    init(services: FridayOrgHostModel.Services) {
        _model = StateObject(wrappedValue: FridayOrgHostModel(services: services))
    }

    var body: some View {
        ZStack {
            FridayVaultBackdrop(motionEnabled: false).ignoresSafeArea()
            if let store = model.store {
                FridayOrgAdminView(store: store, onBack: { model.close() })
            } else {
                organizationList
            }
        }
        .task { await model.load() }
        .navigationBarHidden(model.store != nil)
    }

    private var organizationList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                FridayVaultBrandHeader(
                    title: "ORGANISATIONEN",
                    subtitle: model.host,
                    status: model.organizations.isEmpty ? nil : "\(model.organizations.count) ORGANISATION(EN)",
                    statusSymbol: "building.2",
                    statusColor: FridayVaultDesign.cyan
                )
                .padding(.top, 8)

                if model.loading {
                    HStack(spacing: 8) {
                        ProgressView().tint(FridayVaultDesign.cyan)
                        Text("Organisationen werden geladen …")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(FridayVaultDesign.secondary)
                    }
                    .frame(maxWidth: .infinity)
                } else if model.organizations.isEmpty {
                    FridayBanner(
                        symbol: "building.2",
                        title: "Dein Konto gehört keiner Organisation an",
                        detail: "Sammlungen, Mitglieder und geteilte Einträge gibt es nur in einer Organisation. Anlegen geht in der Mac-App oder im Web-Tresor — hier erscheint sie danach.",
                        tint: FridayVaultDesign.cyan
                    )
                } else {
                    ForEach(model.organizations, id: \.id) { organization in
                        FridayAdminRow(
                            initials: FridayAdmin.initials(organization.name),
                            title: organization.name,
                            subtitle: roleTitle(organization.type),
                            subtitleTint: FridayVaultDesign.green,
                            statusColor: FridayVaultDesign.green,
                            onTap: { model.open(organization) }
                        ) {
                            Image(systemName: "chevron.right")
                                .foregroundStyle(FridayVaultDesign.secondary)
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func roleTitle(_ type: OrganizationUserType) -> String {
        switch type {
        case .owner: "Eigentümer"
        case .admin: "Administrator"
        case .custom: "Eigene Rechte"
        default: "Mitglied"
        }
    }
}

// MARK: - Admin Console

struct FridayOrgAdminView: View {
    @ObservedObject var store: FridayOrgStore
    let onBack: () -> Void
    @SwiftUI.State private var tab = 0
    @SwiftUI.State private var menu: FridayMenu?

    private let tabs = OrgPanelTab.allCases

    var body: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(FridayVaultDesign.separator).frame(height: 1)
            switch store.phase {
            case .connecting, .opening:
                VStack(spacing: 10) {
                    ProgressView().tint(FridayVaultDesign.cyan)
                    Text("Verbindung wird aufgebaut …")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(FridayVaultDesign.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case let .failed(message):
                VStack(spacing: 14) {
                    FridayBanner(symbol: "exclamationmark.triangle.fill", title: "Zugang nicht möglich", detail: message, tint: FridayAdmin.amber)
                    Button { Task { await store.connect() } } label: { Label("Erneut versuchen", systemImage: "arrow.clockwise") }
                        .buttonStyle(FridayPrimaryButtonStyle())
                }
                .padding(16)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            case .open:
                VStack(spacing: 0) {
                    FridayChips(titles: tabs.map(\.title), selection: $tab)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .onChange(of: tab) { value in store.selectedTab = tabs[value] }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            if let notice = store.notice {
                                FridayBanner(
                                    symbol: store.noticeIsWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                    title: store.noticeIsWarning ? "Hinweis" : "Nachgeprüft",
                                    detail: notice,
                                    tint: store.noticeIsWarning ? FridayAdmin.amber : FridayVaultDesign.green
                                ) { store.setNotice(nil, warning: false) }
                            }
                            switch store.selectedTab {
                            case .collections: FridayOrgCollectionsSection(store: store, menu: $menu)
                            case .members: FridayOrgMembersSection(store: store, menu: $menu)
                            case .groups: FridayOrgGroupsSection(store: store, menu: $menu)
                            case .reports: FridayOrgReportsSection(store: store)
                            case .policies: FridayOrgPoliciesSection(store: store)
                            case .settings: FridayOrgSettingsSection(store: store)
                            }
                        }
                        .padding(16)
                        .padding(.bottom, 32)
                    }
                }
            }
        }
        .sheet(item: $menu) { FridayMenuSheet(menu: $0) }
        .onAppear { tab = tabs.firstIndex(of: store.selectedTab) ?? 0 }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onBack) {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left").font(.system(size: 10, weight: .bold))
                    Text("ORGANISATIONEN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                }
                .foregroundStyle(FridayVaultDesign.cyan)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                        .fill(FridayVaultDesign.cyan.opacity(0.1))
                        .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.cyan.opacity(0.35)))
                )
            }
            .buttonStyle(.plain)
            HStack(spacing: 12) {
                FridayAvatar(initials: FridayAdmin.initials(store.organizationName), size: 48, statusColor: store.phase == .open ? FridayVaultDesign.green : nil)
                VStack(alignment: .leading, spacing: 3) {
                    Text(store.organizationName)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(FridayVaultDesign.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("ADMIN CONSOLE · \(store.host)".uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(FridayVaultDesign.cyan)
                        .lineLimit(1)
                }
                Spacer()
                if store.isBusy {
                    ProgressView().tint(FridayVaultDesign.cyan)
                } else if store.phase == .open {
                    FridayIconButton(symbol: "arrow.clockwise") { Task { await store.reloadAll() } }
                }
            }
            if store.phase == .open, !store.vaultIsUnlocked {
                FridayBadgeView(badge: FridayBadge(text: "Tresor gesperrt", color: FridayAdmin.amber))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
    }
}

// MARK: - Sammlungen

private struct FridayOrgCollectionsSection: View {
    @ObservedObject var store: FridayOrgStore
    @Binding var menu: FridayMenu?
    @SwiftUI.State private var search = ""
    @SwiftUI.State private var newCollection = false
    @SwiftUI.State private var editingCollection: OrgCollection?
    @SwiftUI.State private var adopting = false
    @SwiftUI.State private var assigning: OrgItem?
    @SwiftUI.State private var pendingDeletion: OrgCollection?
    @SwiftUI.State private var pendingTrash: OrgItem?

    private var filterTitles: [String] {
        ["Sammlungen", "Alle Einträge", "Papierkorb"] + store.collections.map(\.name)
    }

    private var filterIndex: Binding<Int> {
        Binding(
            get: {
                switch store.vaultFilter {
                case .overview: 0
                case .allItems, .type: 1
                case .trash: 2
                case let .collection(id): (store.collections.firstIndex { $0.id == id }.map { $0 + 3 }) ?? 0
                }
            },
            set: { index in
                switch index {
                case 0: store.vaultFilter = .overview
                case 1: store.vaultFilter = .allItems
                case 2: store.vaultFilter = .trash
                default:
                    let collectionIndex = index - 3
                    if store.collections.indices.contains(collectionIndex) {
                        store.vaultFilter = .collection(store.collections[collectionIndex].id)
                    }
                }
            }
        )
    }

    private var visibleItems: [OrgItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let source = store.vaultFilter == .trash ? store.trash : store.items
        return source
            .filter { item in
                switch store.vaultFilter {
                case .overview, .allItems, .trash: true
                case let .type(type): item.type == type
                case let .collection(id): item.collectionIDs.contains(id)
                }
            }
            .filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.subtitle.lowercased().contains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FridayChips(titles: filterTitles, selection: filterIndex)

            HStack(spacing: 8) {
                TextField(store.vaultFilter == .overview ? "Sammlung durchsuchen" : "Einträge durchsuchen", text: $search)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .foregroundStyle(FridayVaultDesign.text)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                            .fill(FridayAdmin.rowFill)
                            .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge))
                    )
                Button {
                    menu = FridayMenu(title: "NEU", items: [
                        FridayMenuItem(title: "Sammlung", symbol: "archivebox", disabled: !store.vaultIsUnlocked) { newCollection = true },
                        FridayMenuItem(title: "Eintrag aus dem persönlichen Tresor übernehmen", symbol: "arrow.right.square", disabled: store.collections.isEmpty || !store.vaultIsUnlocked) { adopting = true },
                    ])
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(FridayPrimaryButtonStyle(compact: true))
                .disabled(store.isBusy)
            }

            if !store.vaultIsUnlocked {
                FridayBanner(symbol: "lock.fill", title: "Tresor gesperrt", detail: "Sammlungen und Einträge brauchen den entsperrten Tresor.", tint: FridayAdmin.amber)
            } else if store.vaultFilter == .overview {
                collectionRows
            } else if store.vaultFilter == .trash {
                trashRows
            } else {
                itemRows
            }
        }
        .sheet(isPresented: $newCollection) { FridayCollectionSheet(store: store, collection: nil) }
        .sheet(item: $editingCollection) { FridayCollectionSheet(store: store, collection: $0) }
        .sheet(isPresented: $adopting) { FridayAdoptSheet(store: store) }
        .sheet(item: $assigning) { item in
            FridayItemCollectionsSheet(item: item, collections: store.collections) { ids in
                Task { await store.setItemCollections(ids, for: item) }
            }
        }
        .sheet(item: $pendingDeletion) { collection in
            FridayConfirmSheet(
                title: "Sammlung löschen",
                message: "Damit verschwindet „\(collection.name)“ für alle Mitglieder. Einträge, die nur in dieser Sammlung liegen, sind danach nicht mehr erreichbar.",
                confirmation: collection.name
            ) { Task { await store.deleteCollection(collection) } }
        }
        .sheet(item: $pendingTrash) { item in
            FridayConfirmSheet(
                title: "Eintrag in den Papierkorb",
                message: "„\(item.name)“ verschwindet für alle Mitglieder der Organisation und lässt sich nur aus dem Papierkorb zurückholen.",
                confirmation: item.name
            ) { Task { await store.trashItem(item) } }
        }
    }

    private var visibleCollections: [OrgCollection] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.collections.filter { query.isEmpty || $0.name.lowercased().contains(query) }
    }

    @ViewBuilder
    private var collectionRows: some View {
        if visibleCollections.isEmpty {
            FridayBanner(
                symbol: "archivebox",
                title: store.collections.isEmpty ? "Noch keine Sammlung" : "Keine Sammlung passt zur Suche",
                detail: store.collections.isEmpty ? "Über „+ › Sammlung“ anlegen — mit Zugriff für Mitglieder und Gruppen im selben Dialog." : "Suche nach dem Namen.",
                tint: FridayVaultDesign.cyan
            )
        }
        ForEach(visibleCollections) { collection in
            FridayAdminRow(
                symbol: "archivebox",
                title: collection.name,
                subtitle: "\(store.items.filter { $0.collectionIDs.contains(collection.id) }.count) Einträge · \(store.members.filter { $0.seesEverything || $0.collectionIDs.contains(collection.id) }.count) Mitglieder",
                subtitleTint: FridayVaultDesign.green,
                detail: store.ownPermissionTitle(for: collection),
                onTap: { store.vaultFilter = .collection(collection.id) }
            ) {
                FridayIconButton(symbol: "ellipsis") {
                    menu = FridayMenu(title: collection.name.uppercased(), items: [
                        FridayMenuItem(title: "Zugriff verwalten", symbol: "person.2.badge.key") { editingCollection = collection },
                        FridayMenuItem(title: "Einträge anzeigen", symbol: "tray.full") { store.vaultFilter = .collection(collection.id) },
                        FridayMenuItem(title: "Löschen …", symbol: "trash", destructive: true) { pendingDeletion = collection },
                    ])
                }
            }
        }
    }

    @ViewBuilder
    private var itemRows: some View {
        if visibleItems.isEmpty {
            FridayBanner(
                symbol: "tray",
                title: store.items.isEmpty ? "Noch kein Eintrag in dieser Organisation" : "Kein Eintrag passt zu Filter und Suche",
                detail: store.items.isEmpty ? "Einträge entstehen im Tresor der App oder werden aus dem persönlichen Tresor übernommen." : "Filter oder Suche ändern.",
                tint: FridayVaultDesign.cyan
            )
        }
        ForEach(visibleItems) { item in
            FridayAdminRow(
                symbol: symbol(for: item.type),
                title: item.name,
                subtitle: item.subtitle,
                badges: item.collectionIDs.prefix(3).map { FridayBadge(text: store.collectionName($0) ?? "Sammlung", color: FridayVaultDesign.cyan) }
            ) {
                FridayIconButton(symbol: "ellipsis") {
                    menu = FridayMenu(title: item.name.uppercased(), items: [
                        FridayMenuItem(title: "Sammlungen zuweisen", symbol: "archivebox") { assigning = item },
                        FridayMenuItem(title: "In den Papierkorb …", symbol: "trash", destructive: true) { pendingTrash = item },
                    ])
                }
            }
        }
    }

    @ViewBuilder
    private var trashRows: some View {
        if visibleItems.isEmpty {
            FridayBanner(symbol: "trash", title: "Der Papierkorb der Organisation ist leer", detail: "Gelöschte Organisationseinträge landen hier und lassen sich wiederherstellen.", tint: FridayVaultDesign.cyan)
        }
        ForEach(visibleItems) { item in
            FridayAdminRow(
                symbol: symbol(for: item.type),
                title: item.name,
                subtitle: item.deletedDate.map { "Gelöscht \(FridayAdmin.relative($0))" } ?? "Gelöscht",
                subtitleTint: FridayAdmin.red
            ) {
                Button { Task { await store.restoreItem(item) } } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(FridayPrimaryButtonStyle(compact: true))
                    .disabled(store.isBusy)
            }
        }
    }

    private func symbol(for type: CipherType) -> String {
        switch type {
        case .login: "globe"
        case .card: "creditcard"
        case .identity: "person.text.rectangle"
        case .secureNote: "note.text"
        case .sshKey: "key.horizontal"
        default: "doc"
        }
    }
}

// MARK: - Mitglieder

private struct FridayOrgMembersSection: View {
    @ObservedObject var store: FridayOrgStore
    @Binding var menu: FridayMenu?
    @SwiftUI.State private var search = ""
    @SwiftUI.State private var inviting = false
    @SwiftUI.State private var inviteEmail = ""
    @SwiftUI.State private var editing: OrgMember?
    @SwiftUI.State private var pendingRemoval: OrgMember?

    private var visibleMembers: [OrgMember] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.members.filter { query.isEmpty || $0.email.lowercased().contains(query) || ($0.name ?? "").lowercased().contains(query) }
    }

    private var awaiting: Int { store.members.filter { $0.status == .accepted }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                FridayStatTile(label: "Mitglieder", value: "\(store.members.count)")
                FridayStatTile(label: "Eingeladen", value: "\(store.members.filter { $0.status == .invited }.count)", color: FridayAdmin.amber)
                FridayStatTile(label: "Warten", value: "\(awaiting)", color: awaiting > 0 ? FridayVaultDesign.green : FridayVaultDesign.secondary)
            }
            Button { inviting = true } label: { Label("Mitglied einladen", systemImage: "person.badge.plus") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(store.isBusy)

            if awaiting > 0 {
                FridayCard(
                    title: "\(awaiting) Mitglied(er) warten auf Bestätigung",
                    symbol: "person.crop.circle.badge.checkmark",
                    accent: FridayVaultDesign.green,
                    detail: store.vaultIsUnlocked ? "Bestätigen verschlüsselt den Organisationsschlüssel für jedes Mitglied — erst danach sieht es die Sammlungen." : "Zum Bestätigen muss der Tresor entsperrt sein."
                ) {
                    Button { Task { await store.confirmAllAccepted() } } label: { Label("Alle bestätigen", systemImage: "checkmark.seal") }
                        .buttonStyle(FridayPrimaryButtonStyle())
                        .disabled(store.isBusy || !store.vaultIsUnlocked)
                }
            }
            if store.mailEnabled == false {
                FridayBanner(symbol: "envelope.badge", title: "Dieser Server verschickt keine Mail", detail: "Die Person registriert sich selbst und nimmt die Einladung im Web-Tresor an — danach steht sie hier als „Angenommen“.", tint: FridayAdmin.amber)
            }

            TextField("Mitglieder durchsuchen", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .foregroundStyle(FridayVaultDesign.text)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                        .fill(FridayAdmin.rowFill)
                        .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge))
                )

            if visibleMembers.isEmpty {
                FridayBanner(symbol: "person.slash", title: store.members.isEmpty ? "Keine Mitglieder gemeldet" : "Kein Mitglied passt zur Suche", detail: "", tint: FridayVaultDesign.cyan)
            }
            ForEach(visibleMembers) { member in
                memberRow(member)
            }
        }
        .sheet(isPresented: $inviting) { FridayMemberSheet(store: store, member: nil, initialEmail: inviteEmail) }
        .sheet(item: $editing) { FridayMemberSheet(store: store, member: $0) }
        .sheet(item: $pendingRemoval) { member in
            FridayConfirmSheet(
                title: "Mitglied entfernen",
                message: "„\(member.displayName)“ verliert den Zugriff auf alle geteilten Einträge dieser Organisation.",
                confirmation: member.email
            ) { Task { await store.remove(member) } }
        }
        .onAppear {
            if let pending = store.takePendingInvite() {
                inviteEmail = pending
                inviting = true
            }
        }
    }

    private func memberRow(_ member: OrgMember) -> some View {
        var badges: [FridayBadge] = []
        if member.twoFactorEnabled == true { badges.append(FridayBadge(text: "2FA", color: FridayVaultDesign.green)) }
        badges.append(FridayBadge(text: member.role?.title ?? "Rolle unbekannt", color: roleColor(member.role)))
        badges.append(FridayBadge(text: member.status?.title ?? "Stand unbekannt", color: statusColor(member.status)))
        let canConfirm = store.vaultIsUnlocked
        return FridayAdminRow(
            initials: FridayAdmin.initials(member.displayName),
            title: member.displayName,
            subtitle: member.name == nil ? accessSummary(member) : member.email,
            subtitleTint: member.status == .confirmed ? FridayVaultDesign.green : FridayVaultDesign.secondary,
            detail: member.name == nil ? nil : accessSummary(member),
            statusColor: member.status == .confirmed ? FridayVaultDesign.green : nil,
            badges: badges,
            onTap: { editing = member }
        ) {
            if member.status?.awaitsConfirmation == true {
                Button { Task { await store.confirm(member) } } label: { Image(systemName: "checkmark.seal") }
                    .buttonStyle(FridayPrimaryButtonStyle(compact: true))
                    .disabled(store.isBusy || !canConfirm)
            }
            FridayIconButton(symbol: "ellipsis") {
                var items: [FridayMenuItem] = [
                    FridayMenuItem(title: "Zugriff verwalten", symbol: "person.badge.key") { editing = member },
                ]
                if member.status?.awaitsConfirmation == true {
                    items.append(FridayMenuItem(title: "Bestätigen", symbol: "checkmark.seal", disabled: !canConfirm) { Task { await store.confirm(member) } })
                }
                if member.status == .invited {
                    items.append(FridayMenuItem(title: "Einladung erneut senden", symbol: "paperplane") { Task { await store.resendInvite(member) } })
                }
                if member.status == .revoked {
                    items.append(FridayMenuItem(title: "Zugriff wiederherstellen", symbol: "lock.open") { Task { await store.restore(member) } })
                } else {
                    items.append(FridayMenuItem(title: "Zugriff entziehen", symbol: "lock") { Task { await store.revoke(member) } })
                }
                items.append(FridayMenuItem(title: "Aus Organisation entfernen …", symbol: "trash", destructive: true) { pendingRemoval = member })
                menu = FridayMenu(title: member.displayName.uppercased(), items: items)
            }
        }
    }

    private func accessSummary(_ member: OrgMember) -> String {
        var parts: [String] = []
        if member.seesEverything {
            parts.append("Sieht alle Sammlungen")
        } else if member.collectionAccess.isEmpty {
            parts.append("Keine Sammlung zugeordnet")
        } else {
            let names = member.collectionAccess.compactMap { store.collectionName($0.id) }
            parts.append(names.isEmpty ? "\(member.collectionAccess.count) Sammlung(en)" : names.prefix(2).joined(separator: " · ") + (names.count > 2 ? " · +\(names.count - 2)" : ""))
        }
        if !member.groupIDs.isEmpty { parts.append("\(member.groupIDs.count) Gruppe(n)") }
        return parts.joined(separator: " · ")
    }

    private func statusColor(_ status: OrgMemberStatus?) -> Color {
        switch status {
        case .confirmed: FridayVaultDesign.green
        case .accepted: FridayVaultDesign.cyan
        case .invited: FridayAdmin.amber
        case .revoked: FridayAdmin.red
        case .none: FridayVaultDesign.secondary
        }
    }

    private func roleColor(_ role: OrgMemberRole?) -> Color {
        switch role {
        case .owner: FridayAdmin.amber
        case .admin: FridayVaultDesign.cyan
        case .manager: FridayVaultDesign.electric
        case .user, .custom, .none: FridayVaultDesign.secondary
        }
    }
}

// MARK: - Gruppen

private struct FridayOrgGroupsSection: View {
    @ObservedObject var store: FridayOrgStore
    @Binding var menu: FridayMenu?
    @SwiftUI.State private var newName = ""
    @SwiftUI.State private var renaming: OrgGroup?
    @SwiftUI.State private var editingMembers: OrgGroup?
    @SwiftUI.State private var editingCollections: OrgGroup?
    @SwiftUI.State private var pendingDeletion: OrgGroup?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FridayCard(title: "Neue Gruppe", symbol: "person.3", detail: "Gruppen bündeln Sammlungszugriffe — ein Mitglied in der Gruppe bekommt alle ihre Sammlungen.") {
                HStack(spacing: 8) {
                    TextField("Name", text: $newName)
                        .textFieldStyle(.plain)
                        .foregroundStyle(FridayVaultDesign.text)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).fill(FridayAdmin.rowFill).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge)))
                    Button {
                        let name = newName
                        newName = ""
                        Task { await store.createGroup(name: name) }
                    } label: { Image(systemName: "plus") }
                        .buttonStyle(FridayPrimaryButtonStyle(compact: true))
                        .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty || store.isBusy)
                }
            }
            if store.groups.isEmpty {
                FridayBanner(symbol: "person.3", title: "Keine Gruppe angelegt", detail: "", tint: FridayVaultDesign.cyan)
            }
            ForEach(store.groups) { group in
                FridayAdminRow(
                    symbol: "person.3",
                    title: group.name,
                    subtitle: "\(store.members.filter { $0.groupIDs.contains(group.id) }.count) Mitglied(er) · \(group.collectionIDs.count) Sammlung(en)",
                    subtitleTint: FridayVaultDesign.green,
                    onTap: { editingMembers = group }
                ) {
                    FridayIconButton(symbol: "ellipsis") {
                        menu = FridayMenu(title: group.name.uppercased(), items: [
                            FridayMenuItem(title: "Mitglieder", symbol: "person.2") { editingMembers = group },
                            FridayMenuItem(title: "Sammlungen", symbol: "archivebox") { editingCollections = group },
                            FridayMenuItem(title: "Umbenennen", symbol: "pencil") { renaming = group },
                            FridayMenuItem(title: "Löschen …", symbol: "trash", destructive: true) { pendingDeletion = group },
                        ])
                    }
                }
            }
        }
        .sheet(item: $renaming) { group in
            FridayNameSheet(title: "Gruppe umbenennen", initial: group.name) { name in Task { await store.renameGroup(group, to: name) } }
        }
        .sheet(item: $editingMembers) { FridayGroupMembersSheet(store: store, group: $0) }
        .sheet(item: $editingCollections) { FridayGroupCollectionsSheet(store: store, group: $0) }
        .sheet(item: $pendingDeletion) { group in
            FridayConfirmSheet(title: "Gruppe löschen", message: "„\(group.name)“ wird aufgelöst. Die Mitglieder bleiben, verlieren aber die Zugriffe der Gruppe.", confirmation: group.name) {
                Task { await store.deleteGroup(group) }
            }
        }
    }
}

// MARK: - Berichte

private struct FridayOrgReportsSection: View {
    @ObservedObject var store: FridayOrgStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(store.eventsLoaded ? "Ereignisprotokoll · 30 Tage · \(store.events.count)" : "Ereignisprotokoll wird geladen …")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FridayVaultDesign.secondary)
                Spacer()
                FridayIconButton(symbol: "arrow.clockwise", disabled: store.isBusy) { Task { await store.reloadEvents() } }
            }
            if store.eventsLoaded, store.events.isEmpty {
                FridayBanner(symbol: "list.bullet.rectangle", title: "Keine Ereignisse gemeldet", detail: "Vaultwarden führt das Protokoll nur mit gesetztem ORG_EVENTS_ENABLED.", tint: FridayVaultDesign.cyan)
            }
            ForEach(store.events) { event in
                HStack(spacing: 12) {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(FridayVaultDesign.cyan)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(event.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FridayVaultDesign.text)
                        Text(subtitle(event))
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FridayVaultDesign.secondary)
                            .lineLimit(2)
                    }
                    Spacer()
                    Text(FridayAdmin.relative(event.date))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(FridayVaultDesign.secondary)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).fill(FridayAdmin.rowFill))
            }
        }
        .task { if !store.eventsLoaded { await store.reloadEvents() } }
    }

    private func subtitle(_ event: OrgEvent) -> String {
        var parts: [String] = []
        if let actor = store.memberName(userID: event.actingUserID) { parts.append("durch \(actor)") }
        if let member = event.memberID, let name = store.members.first(where: { $0.id == member })?.displayName { parts.append("Mitglied \(name)") }
        if let collection = event.collectionID, let name = store.collectionName(collection) { parts.append("Sammlung \(name)") }
        if let cipher = event.cipherID, let name = store.items.first(where: { $0.id == cipher })?.name { parts.append("Eintrag \(name)") }
        return parts.isEmpty ? event.date : parts.joined(separator: " · ")
    }
}

// MARK: - Richtlinien

private struct FridayOrgPoliciesSection: View {
    @ObservedObject var store: FridayOrgStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Richtlinien gelten für alle Mitglieder. Was der Server nicht gemeldet hat, steht als „nicht gemeldet“ — nicht als „aus“.")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(FridayVaultDesign.secondary)
            ForEach(OrgPolicyType.allCases) { type in
                let known = store.policies.first { $0.typeRaw == type.rawValue }
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(type.title)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(FridayVaultDesign.text)
                        Text(type.explanation)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FridayVaultDesign.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        if known == nil {
                            FridayBadgeView(badge: FridayBadge(text: "nicht gemeldet", color: FridayVaultDesign.secondary))
                        }
                    }
                    Spacer(minLength: 8)
                    Toggle("", isOn: Binding(
                        get: { known?.enabled ?? false },
                        set: { value in Task { await store.setPolicy(type, enabled: value) } }
                    ))
                    .labelsHidden()
                    .tint(FridayVaultDesign.cyan)
                    .disabled(store.isBusy)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).fill(FridayAdmin.rowFill).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.edge)))
            }
        }
    }
}

// MARK: - Einstellungen

private struct FridayOrgSettingsSection: View {
    @ObservedObject var store: FridayOrgStore
    @SwiftUI.State private var renaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            FridayCard(title: "Organisationsinfo", symbol: "building.2") {
                row("Name", store.organizationName)
                row("Rechnungsadresse", store.billingEmail ?? "nicht gemeldet")
                row("Kennung", store.organizationID)
                row("Server", store.host)
                row("Eigene Rolle", store.ownMembership?.role?.title ?? "nicht belegt")
                Button { renaming = true } label: { Label("Name und Rechnungsadresse ändern", systemImage: "pencil") }
                    .buttonStyle(FridaySecondaryButtonStyle())
                    .disabled(store.isBusy)
            }
            FridayBanner(symbol: "info.circle", title: "Löschen und Anlegen", detail: "Organisationen anlegen und löschen geht in der Mac-App oder im Web-Tresor.", tint: FridayVaultDesign.cyan)
        }
        .sheet(isPresented: $renaming) {
            FridayRenameSheet(name: store.organizationName, billingEmail: store.billingEmail ?? "") { name, email in
                Task { await store.rename(to: name, billingEmail: email) }
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(FridayVaultDesign.secondary)
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(FridayVaultDesign.text)
                .textSelection(.enabled)
        }
    }
}
