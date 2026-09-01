// swiftlint:disable file_length type_body_length function_body_length line_length

import BitwardenKit
import SwiftUI

// MARK: - Zugriffszeile

/// „Wer darf was": Häkchen + Berechtigungsstufe (eigenes Blatt statt Systemmenü).
struct FridayAccessRow: View {
    let title: String
    var subtitle: String?
    @Binding var access: OrgCollectionAccess?
    let id: String
    @SwiftUI.State private var choosing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle(isOn: Binding(
                get: { access != nil },
                set: { on in access = on ? OrgCollectionAccess(id: id, permission: .canView) : nil }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text)
                    if let subtitle {
                        Text(subtitle).font(.system(size: 10, design: .monospaced)).foregroundStyle(FridayVaultDesign.secondary)
                    }
                }
            }
            .tint(FridayVaultDesign.cyan)
            if access != nil {
                Button { choosing = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: symbol(access?.permission ?? .canView))
                        Text(access?.permission.title ?? OrgPermission.canView.title)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down").font(.system(size: 10, weight: .bold)).opacity(0.7)
                    }
                }
                .buttonStyle(FridaySecondaryButtonStyle(compact: true))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).fill(FridayAdmin.rowFill).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.edge)))
        .sheet(isPresented: $choosing) {
            FridayMenuSheet(menu: FridayMenu(title: "BERECHTIGUNG", items: OrgPermission.allCases.map { permission in
                FridayMenuItem(title: permission.title, symbol: symbol(permission)) { access?.permission = permission }
            }))
        }
    }

    private func symbol(_ permission: OrgPermission) -> String {
        switch permission {
        case .canView: "eye"
        case .canViewExceptPasswords: "eye.slash"
        case .canEdit: "pencil"
        case .canEditExceptPasswords: "pencil.slash"
        case .canManage: "person.badge.key"
        }
    }
}

// MARK: - Feld

struct FridayField: View {
    let placeholder: String
    @Binding var text: String
    var secure = false

    var body: some View {
        Group {
            if secure {
                SecureField(placeholder, text: $text)
            } else {
                TextField(placeholder, text: $text)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
        }
        .textFieldStyle(.plain)
        .font(.system(size: 15))
        .foregroundStyle(FridayVaultDesign.text)
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).fill(FridayVaultDesign.void.opacity(0.6)).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge)))
    }
}

// MARK: - Sammlung anlegen / Zugriff

struct FridayCollectionSheet: View {
    @ObservedObject var store: FridayOrgStore
    let collection: OrgCollection?
    @SwiftUI.State private var tab = 0
    @SwiftUI.State private var name: String
    @SwiftUI.State private var users: [String: OrgCollectionAccess] = [:]
    @SwiftUI.State private var groups: [String: OrgCollectionAccess] = [:]
    @SwiftUI.State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    init(store: FridayOrgStore, collection: OrgCollection?) {
        self.store = store
        self.collection = collection
        _name = SwiftUI.State(initialValue: collection?.name ?? "")
    }

    var body: some View {
        FridaySheet(
            title: collection == nil ? "Neue Sammlung" : collection?.name ?? "Sammlung",
            caption: collection == nil ? "Sammlungsinfo und Zugriff" : "Zugriff verwalten",
            symbol: "archivebox"
        ) {
            FridayChips(titles: ["Sammlungsinfo", "Zugriff"], selection: $tab)
            if tab == 0 {
                FridayCard(title: "Name", symbol: "textformat", detail: "„Marketing/Kampagnen“ legt die Sammlung unter „Marketing“ an.") {
                    FridayField(placeholder: "Name der Sammlung", text: $name)
                }
            } else {
                Text("Mitglieder").font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text)
                Text("Eigentümer und Administratoren sehen jede Sammlung — sie brauchen keinen Eintrag hier.")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(FridayVaultDesign.secondary)
                ForEach(store.members.filter { !$0.seesEverything }) { member in
                    FridayAccessRow(title: member.displayName, subtitle: member.name == nil ? nil : member.email, access: Binding(get: { users[member.id] }, set: { users[member.id] = $0 }), id: member.id)
                }
                Text("Gruppen").font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text).padding(.top, 6)
                if store.groups.isEmpty {
                    Text("Keine Gruppe angelegt.").font(.system(size: 11, weight: .medium)).foregroundStyle(FridayVaultDesign.secondary)
                }
                ForEach(store.groups) { group in
                    FridayAccessRow(title: group.name, access: Binding(get: { groups[group.id] }, set: { groups[group.id] = $0 }), id: group.id)
                }
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                let access = OrgCollectionDetails(users: store.members.compactMap { users[$0.id] }, groups: store.groups.compactMap { groups[$0.id] })
                if let collection {
                    Task { await store.setCollectionAccess(collection, name: name, access: access) }
                } else {
                    Task { await store.createCollection(name: name, access: access) }
                }
                dismiss()
            } label: {
                Label(collection == nil ? "Anlegen" : "Speichern", systemImage: "checkmark")
            }
            .buttonStyle(FridayPrimaryButtonStyle())
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || (collection != nil && !loaded))
        }
        .task {
            guard let collection else { loaded = true; return }
            await store.loadCollectionDetails(collection)
            let details = store.collectionDetails[collection.id] ?? OrgCollectionDetails()
            for entry in details.users { users[entry.id] = entry }
            for entry in details.groups { groups[entry.id] = entry }
            loaded = true
        }
    }
}

// MARK: - Mitglied einladen / Zugriff

struct FridayMemberSheet: View {
    @ObservedObject var store: FridayOrgStore
    let member: OrgMember?
    @SwiftUI.State private var tab = 0
    @SwiftUI.State private var email: String
    @SwiftUI.State private var role: OrgMemberRole
    @SwiftUI.State private var collections: [String: OrgCollectionAccess] = [:]
    @SwiftUI.State private var groups: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    init(store: FridayOrgStore, member: OrgMember?, initialEmail: String = "") {
        self.store = store
        self.member = member
        _email = SwiftUI.State(initialValue: initialEmail)
        _role = SwiftUI.State(initialValue: member?.role ?? .user)
        var initial: [String: OrgCollectionAccess] = [:]
        for entry in member?.collectionAccess ?? [] { initial[entry.id] = entry }
        _collections = SwiftUI.State(initialValue: initial)
        _groups = SwiftUI.State(initialValue: Set(member?.groupIDs ?? []))
    }

    var body: some View {
        FridaySheet(
            title: member == nil ? "Mitglied einladen" : member?.displayName ?? "Mitglied",
            caption: member == nil ? "Rolle · Sammlungen · Gruppen" : "Zugriff verwalten",
            symbol: member == nil ? "person.badge.plus" : nil,
            initials: member.map { FridayAdmin.initials($0.displayName) }
        ) {
            FridayChips(titles: ["Rolle", "Sammlungen", "Gruppen"], selection: $tab)
            switch tab {
            case 0:
                if member == nil {
                    FridayCard(title: "E-Mail-Adresse", symbol: "envelope") {
                        FridayField(placeholder: "name@firma.de", text: $email)
                    }
                }
                ForEach(OrgMemberRole.assignable) { candidate in
                    Button { role = candidate } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: role == candidate ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(role == candidate ? FridayVaultDesign.cyan : FridayVaultDesign.secondary)
                                .padding(.top, 2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(candidate.title).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text)
                                Text(candidate.explanation).font(.system(size: 11, weight: .medium)).foregroundStyle(FridayVaultDesign.secondary).fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer()
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).fill(role == candidate ? FridayVaultDesign.cyan.opacity(0.13) : FridayAdmin.rowFill).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(role == candidate ? FridayVaultDesign.cyan.opacity(0.55) : FridayVaultDesign.edge)))
                    }
                    .buttonStyle(.plain)
                }
            case 1:
                if role.seesEverything {
                    FridayBanner(symbol: "info.circle", title: "Sieht als \(role.title) jede Sammlung", detail: "Die Auswahl hier bleibt ohne Wirkung.", tint: FridayAdmin.amber)
                }
                if store.collections.isEmpty {
                    Text("Noch keine Sammlung in dieser Organisation.").font(.system(size: 12, weight: .medium)).foregroundStyle(FridayVaultDesign.secondary)
                }
                ForEach(store.collections) { collection in
                    FridayAccessRow(title: collection.name, access: Binding(get: { collections[collection.id] }, set: { collections[collection.id] = $0 }), id: collection.id)
                }
            default:
                if store.groups.isEmpty {
                    Text("Keine Gruppe angelegt.").font(.system(size: 12, weight: .medium)).foregroundStyle(FridayVaultDesign.secondary)
                }
                ForEach(store.groups) { group in
                    Toggle(isOn: Binding(get: { groups.contains(group.id) }, set: { on in if on { groups.insert(group.id) } else { groups.remove(group.id) } })) {
                        Text(group.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text)
                    }
                    .tint(FridayVaultDesign.cyan)
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).fill(FridayAdmin.rowFill).overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.edge)))
                }
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                let access = store.collections.compactMap { collections[$0.id] }
                let groupIDs = store.groups.map(\.id).filter { groups.contains($0) }
                if let member {
                    Task { await store.setMemberAccess(member, role: role, collections: access, groups: groupIDs) }
                } else {
                    Task { await store.invite(email: email, role: role, collections: access, groups: groupIDs) }
                }
                dismiss()
            } label: {
                Label(member == nil ? "Einladen" : "Speichern", systemImage: member == nil ? "paperplane.fill" : "checkmark")
            }
            .buttonStyle(FridayPrimaryButtonStyle())
            .disabled(member == nil && !email.contains("@"))
        }
    }
}

// MARK: - Einträge

struct FridayAdoptSheet: View {
    @ObservedObject var store: FridayOrgStore
    @SwiftUI.State private var search = ""
    @SwiftUI.State private var selectedItemID: String?
    @SwiftUI.State private var selected: Set<String> = []
    @Environment(\.dismiss) private var dismiss

    private var candidates: [OrgItem] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return store.personalItems
            .filter { query.isEmpty || $0.name.lowercased().contains(query) || $0.subtitle.lowercased().contains(query) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        FridaySheet(title: "Aus dem Tresor übernehmen", caption: "persönlicher Eintrag → \(store.organizationName)", symbol: "arrow.right.square") {
            FridayBanner(symbol: "arrow.right.square", title: "Der Eintrag gehört danach der Organisation", detail: "Bitwarden kennt keinen Weg zurück in den persönlichen Tresor.", tint: FridayAdmin.amber)
            FridayField(placeholder: "Persönliche Einträge durchsuchen", text: $search)
            ForEach(candidates.prefix(100)) { item in
                Button { selectedItemID = item.id } label: {
                    HStack(spacing: 10) {
                        Image(systemName: selectedItemID == item.id ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(selectedItemID == item.id ? FridayVaultDesign.cyan : FridayVaultDesign.secondary)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.name).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text).lineLimit(1)
                            Text(item.subtitle).font(.system(size: 11)).foregroundStyle(FridayVaultDesign.secondary).lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).fill(selectedItemID == item.id ? FridayVaultDesign.cyan.opacity(0.14) : FridayAdmin.rowFill))
                }
                .buttonStyle(.plain)
            }
            FridayCard(title: "In welche Sammlung(en)?", symbol: "archivebox") {
                ForEach(store.collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in if on { selected.insert(collection.id) } else { selected.remove(collection.id) } }))
                        .tint(FridayVaultDesign.cyan)
                        .foregroundStyle(FridayVaultDesign.text)
                }
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                if let item = store.personalItems.first(where: { $0.id == selectedItemID }) {
                    let ids = store.collections.map(\.id).filter { selected.contains($0) }
                    Task { await store.adoptItem(item, collectionIDs: ids) }
                }
                dismiss()
            } label: { Label("Übernehmen", systemImage: "arrow.right.square") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(selectedItemID == nil || selected.isEmpty)
        }
    }
}

struct FridayItemCollectionsSheet: View {
    let item: OrgItem
    let collections: [OrgCollection]
    let onSave: ([String]) -> Void
    @SwiftUI.State private var selected: Set<String>
    @Environment(\.dismiss) private var dismiss

    init(item: OrgItem, collections: [OrgCollection], onSave: @escaping ([String]) -> Void) {
        self.item = item
        self.collections = collections
        self.onSave = onSave
        _selected = SwiftUI.State(initialValue: Set(item.collectionIDs))
    }

    var body: some View {
        FridaySheet(title: item.name, caption: "Sammlungen zuweisen", symbol: "archivebox") {
            FridayCard(title: "Sammlungen", symbol: "archivebox", detail: "Mindestens eine Sammlung ist Pflicht. Wer Zugriff auf die Sammlung hat, sieht den Eintrag.") {
                ForEach(collections) { collection in
                    Toggle(collection.name, isOn: Binding(get: { selected.contains(collection.id) }, set: { on in if on { selected.insert(collection.id) } else { selected.remove(collection.id) } }))
                        .tint(FridayVaultDesign.cyan)
                        .foregroundStyle(FridayVaultDesign.text)
                }
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                onSave(collections.map(\.id).filter { selected.contains($0) })
                dismiss()
            } label: { Label("Speichern", systemImage: "checkmark") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(selected.isEmpty || selected == Set(item.collectionIDs))
        }
    }
}

// MARK: - Gruppen

struct FridayGroupMembersSheet: View {
    @ObservedObject var store: FridayOrgStore
    let group: OrgGroup
    @SwiftUI.State private var selected: Set<String> = []
    @SwiftUI.State private var loaded = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FridaySheet(title: group.name, caption: "Mitglieder der Gruppe", symbol: "person.3") {
            ForEach(store.members) { member in
                Toggle(isOn: Binding(get: { selected.contains(member.id) }, set: { on in if on { selected.insert(member.id) } else { selected.remove(member.id) } })) {
                    Text(member.displayName).font(.system(size: 14, weight: .semibold)).foregroundStyle(FridayVaultDesign.text)
                }
                .tint(FridayVaultDesign.cyan)
                .padding(12)
                .background(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).fill(FridayAdmin.rowFill))
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                Task { await store.setGroupMembers(group, memberIDs: store.members.map(\.id).filter { selected.contains($0) }) }
                dismiss()
            } label: { Label("Speichern", systemImage: "checkmark") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(!loaded)
        }
        .task {
            await store.loadGroupMembers(group)
            selected = Set(store.groupMembers[group.id] ?? store.members.filter { $0.groupIDs.contains(group.id) }.map(\.id))
            loaded = true
        }
    }
}

struct FridayGroupCollectionsSheet: View {
    @ObservedObject var store: FridayOrgStore
    let group: OrgGroup
    @SwiftUI.State private var access: [String: OrgCollectionAccess] = [:]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FridaySheet(title: group.name, caption: "Sammlungen der Gruppe", symbol: "person.3") {
            ForEach(store.collections) { collection in
                FridayAccessRow(title: collection.name, access: Binding(get: { access[collection.id] }, set: { access[collection.id] = $0 }), id: collection.id)
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button {
                Task { await store.setGroupCollections(group, collections: store.collections.compactMap { access[$0.id] }) }
                dismiss()
            } label: { Label("Speichern", systemImage: "checkmark") }
                .buttonStyle(FridayPrimaryButtonStyle())
        }
        .onAppear {
            for id in group.collectionIDs { access[id] = OrgCollectionAccess(id: id, permission: .canView) }
        }
    }
}

// MARK: - Kleine Dialoge

struct FridayNameSheet: View {
    let title: String
    let initial: String
    let onSave: (String) -> Void
    @SwiftUI.State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, onSave: @escaping (String) -> Void) {
        self.title = title
        self.initial = initial
        self.onSave = onSave
        _name = SwiftUI.State(initialValue: initial)
    }

    var body: some View {
        FridaySheet(title: title, caption: initial, symbol: "pencil") {
            FridayCard(title: "Neuer Name", symbol: "textformat") { FridayField(placeholder: "Name", text: $name) }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button { onSave(name); dismiss() } label: { Label("Speichern", systemImage: "checkmark") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || name == initial)
        }
        .fridayHalfSheet()
    }
}

struct FridayRenameSheet: View {
    let onSave: (String, String) -> Void
    @SwiftUI.State private var name: String
    @SwiftUI.State private var billingEmail: String
    private let initialName: String
    private let initialEmail: String
    @Environment(\.dismiss) private var dismiss

    init(name: String, billingEmail: String, onSave: @escaping (String, String) -> Void) {
        self.onSave = onSave
        initialName = name
        initialEmail = billingEmail
        _name = SwiftUI.State(initialValue: name)
        _billingEmail = SwiftUI.State(initialValue: billingEmail)
    }

    var body: some View {
        FridaySheet(title: "Organisation umbenennen", caption: initialName, symbol: "building.2") {
            FridayCard(title: "Name", symbol: "textformat") { FridayField(placeholder: "Name", text: $name) }
            FridayCard(title: "Rechnungsadresse", symbol: "envelope", detail: "Bei Vaultwarden nur ein Pflichtfeld — es wird nichts berechnet.") { FridayField(placeholder: "Rechnungsadresse", text: $billingEmail) }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button { onSave(name, billingEmail); dismiss() } label: { Label("Speichern", systemImage: "checkmark") }
                .buttonStyle(FridayPrimaryButtonStyle())
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !billingEmail.contains("@") || (name == initialName && billingEmail == initialEmail))
        }
    }
}

/// Zerstörerisches verlangt die abgetippte Bestätigung — ein Tipp allein löscht hier nichts.
struct FridayConfirmSheet: View {
    let title: String
    let message: String
    let confirmation: String
    let onConfirm: () -> Void
    @SwiftUI.State private var typed = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        FridaySheet(title: title, caption: "Endgültig · abgetippte Bestätigung", symbol: "trash") {
            FridayBanner(symbol: "exclamationmark.triangle.fill", title: "Das lässt sich nicht einfach rückgängig machen", detail: message, tint: FridayAdmin.red)
            FridayCard(title: "Zum Bestätigen „\(confirmation)“ eintippen", symbol: "keyboard", accent: FridayAdmin.red) {
                FridayField(placeholder: "", text: $typed)
            }
        } footer: {
            Button("Abbrechen") { dismiss() }.buttonStyle(FridaySecondaryButtonStyle())
            Button { onConfirm(); dismiss() } label: { Label("Endgültig", systemImage: "trash.fill") }
                .buttonStyle(FridayPrimaryButtonStyle(destructive: true))
                .disabled(typed.trimmingCharacters(in: .whitespaces).lowercased() != confirmation.lowercased())
        }
    }
}
