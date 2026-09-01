// swiftlint:disable file_length type_body_length function_body_length line_length cyclomatic_complexity

import BitwardenKit
import SwiftUI

// Bausteine der Organisationsverwaltung auf dem iPhone — in der Formsprache der
// F.R.I.D.A.Y.-Loginmaske: Avatar-Zeilen, Glaskarten mit Symbol, Chips, eigene Menüs.

enum FridayAdmin {
    static let amber = Color(red: 1.0, green: 0.66, blue: 0.18)
    static let red = Color(red: 1.0, green: 0.31, blue: 0.4)
    static var cardFill: Color { FridayVaultDesign.panel.opacity(0.94) }
    static var rowFill: Color { FridayVaultDesign.elevated.opacity(0.6) }

    /// Buchstaben für einen Avatar aus Name, E-Mail oder Hostname.
    static func initials(_ text: String) -> String {
        let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.contains("@") {
            let local = cleaned.split(separator: "@").first.map(String.init) ?? cleaned
            let parts = local.split(whereSeparator: { ".-_".contains($0) })
            if parts.count >= 2 { return String(parts[0].prefix(1) + parts[1].prefix(1)).uppercased() }
            return String(local.prefix(2)).uppercased()
        }
        let words = cleaned.split(separator: " ").filter { !$0.isEmpty }
        if words.count >= 2 { return String(words[0].prefix(1) + words[1].prefix(1)).uppercased() }
        let host = cleaned.split(separator: ".").first.map(String.init) ?? cleaned
        return String(host.prefix(2)).uppercased()
    }

    private static let serverFormats: [DateFormatter] = ["yyyy-MM-dd HH:mm:ss ZZZZZ", "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss.SSSSSSS"].map {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = $0
        return formatter
    }

    static func date(_ raw: String?) -> Date? {
        guard let raw, !raw.isEmpty else { return nil }
        for formatter in serverFormats {
            if let date = formatter.date(from: raw) { return date }
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return iso.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func relative(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "nie" }
        guard let date = date(raw) else { return raw }
        return relative(date)
    }

    static func relative(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Avatar

struct FridayAvatar: View {
    let initials: String
    var size: CGFloat = 44
    var statusColor: Color?

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Circle()
                .fill(FridayVaultDesign.deep)
                .overlay(Circle().stroke(FridayVaultDesign.cyan.opacity(0.55), lineWidth: 1.5))
                .overlay(
                    Text(initials)
                        .font(.system(size: size * 0.36, weight: .semibold, design: .rounded))
                        .foregroundStyle(FridayVaultDesign.text)
                )
                .frame(width: size, height: size)
            if let statusColor {
                Circle()
                    .fill(statusColor)
                    .frame(width: size * 0.26, height: size * 0.26)
                    .overlay(Circle().stroke(FridayVaultDesign.void, lineWidth: 2))
            }
        }
    }
}

// MARK: - Abzeichen

struct FridayBadge: Identifiable, Equatable {
    let text: String
    let color: Color
    var id: String { text }
}

struct FridayBadgeView: View {
    let badge: FridayBadge
    var body: some View {
        Text(badge.text.uppercased())
            .font(.system(size: 9, weight: .semibold, design: .monospaced))
            .tracking(0.6)
            .foregroundStyle(badge.color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(badge.color.opacity(0.14)).overlay(Capsule().stroke(badge.color.opacity(0.35), lineWidth: 1)))
    }
}

// MARK: - Zeile

/// Eine Zeile wie in der Kontenliste: Avatar oder Symbolkachel, Titel, getönte Unterzeile,
/// Abzeichen, rechts ein Knopf oder Menü. Auf dem iPhone brechen die Abzeichen in die
/// zweite Zeile um.
struct FridayAdminRow<Trailing: View>: View {
    var initials: String?
    var symbol: String?
    let title: String
    var subtitle: String?
    var subtitleTint: Color = FridayVaultDesign.secondary
    var detail: String?
    var statusColor: Color?
    var badges: [FridayBadge] = []
    var accent: Color = FridayVaultDesign.cyan
    var onTap: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                if let initials {
                    FridayAvatar(initials: initials, size: 42, statusColor: statusColor)
                } else {
                    ZStack {
                        RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                            .fill(accent.opacity(0.1))
                            .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(accent.opacity(0.35)))
                        Image(systemName: symbol ?? "square")
                            .font(.system(size: 17, weight: .light))
                            .foregroundStyle(accent)
                    }
                    .frame(width: 42, height: 42)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(FridayVaultDesign.text)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(subtitleTint)
                            .lineLimit(1)
                    }
                    if let detail {
                        Text(detail)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(FridayVaultDesign.secondary.opacity(0.85))
                            .lineLimit(2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { onTap?() }
                trailing()
            }
            if !badges.isEmpty {
                HStack(spacing: 6) {
                    ForEach(badges) { FridayBadgeView(badge: $0) }
                    Spacer()
                }
                .padding(.leading, 54)
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                .fill(FridayAdmin.rowFill)
                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.edge, lineWidth: 1))
        )
    }
}

// MARK: - Karten

struct FridayCard<Content: View>: View {
    let title: String
    let symbol: String
    var accent: Color = FridayVaultDesign.cyan
    var detail: String?
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: symbol).foregroundStyle(accent)
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(FridayVaultDesign.text)
                Spacer()
            }
            if let detail {
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FridayVaultDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                .fill(FridayAdmin.cardFill)
                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(accent.opacity(0.4), lineWidth: 1))
        )
    }
}

struct FridayBanner: View {
    let symbol: String
    let title: String
    let detail: String
    var tint: Color = FridayVaultDesign.green
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(FridayVaultDesign.text)
                Text(detail)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(FridayVaultDesign.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(FridayVaultDesign.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                .fill(FridayAdmin.cardFill)
                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(tint.opacity(0.45), lineWidth: 1))
        )
    }
}

struct FridayStatTile: View {
    let label: String
    let value: String
    var color: Color = FridayVaultDesign.cyan

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(FridayVaultDesign.secondary)
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(color)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                .fill(FridayAdmin.rowFill)
                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(color.opacity(0.35)))
        )
    }
}

// MARK: - Chips

struct FridayChips: View {
    let titles: [String]
    @Binding var selection: Int

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { index in
                    let active = selection == index
                    Button {
                        selection = index
                    } label: {
                        Text(titles[index])
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(active ? FridayVaultDesign.text : FridayVaultDesign.secondary)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                                    .fill(active ? FridayVaultDesign.cyan.opacity(0.18) : FridayAdmin.rowFill)
                                    .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(active ? FridayVaultDesign.cyan.opacity(0.5) : FridayVaultDesign.edge))
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Knöpfe

struct FridayPrimaryButtonStyle: ButtonStyle {
    var destructive = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(destructive ? Color.white : FridayVaultDesign.void)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                    .fill(destructive ? FridayAdmin.red : FridayVaultDesign.cyan)
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
    }
}

struct FridaySecondaryButtonStyle: ButtonStyle {
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: compact ? 13 : 15, weight: .semibold))
            .foregroundStyle(FridayVaultDesign.text)
            .padding(.horizontal, compact ? 12 : 16)
            .padding(.vertical, compact ? 8 : 12)
            .frame(maxWidth: compact ? nil : .infinity)
            .background(
                RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                    .fill(FridayAdmin.rowFill)
                    .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge))
                    .opacity(configuration.isPressed ? 0.75 : 1)
            )
    }
}

struct FridayIconButton: View {
    let symbol: String
    var disabled = false
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(FridayVaultDesign.secondary)
                .frame(width: 38, height: 36)
                .background(
                    RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous)
                        .fill(FridayAdmin.rowFill)
                        .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerControl, style: .continuous).stroke(FridayVaultDesign.edge))
                )
        }
        .buttonStyle(.plain)
        .disabled(disabled)
    }
}

// MARK: - Menü als Blatt von unten

struct FridayMenuItem: Identifiable {
    let id = UUID()
    let title: String
    let symbol: String
    var destructive = false
    var disabled = false
    let action: () -> Void
}

struct FridayMenu: Identifiable {
    let id = UUID()
    let title: String
    let items: [FridayMenuItem]
}

/// Das Zeilenmenü der Verwaltung: ein Blatt von unten im App-Kleid — kein Systemmenü.
struct FridayMenuSheet: View {
    let menu: FridayMenu
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            FridayVaultDesign.void.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 8) {
                Text(menu.title)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(FridayVaultDesign.secondary)
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                ForEach(menu.items) { item in
                    Button {
                        dismiss()
                        item.action()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: item.symbol)
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 22)
                            Text(item.title)
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                        .foregroundStyle(item.destructive ? FridayAdmin.red : (item.disabled ? FridayVaultDesign.secondary : FridayVaultDesign.text))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 13)
                        .background(
                            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                                .fill(FridayAdmin.rowFill)
                                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.edge))
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(item.disabled)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
        }
        .fridayHalfSheet()
    }
}

/// Halbes Blatt, wo das System es kann — sonst ein ganzes.
private struct FridayHalfSheetModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 16.0, *) {
            content
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        } else {
            content
        }
    }
}

extension View {
    func fridayHalfSheet() -> some View { modifier(FridayHalfSheetModifier()) }
}

// MARK: - Dialograhmen

/// Der Rahmen jedes Dialogs: Kopf mit Avatar oder Symbol, Inhalt, Knöpfe unten.
struct FridaySheet<Content: View, Footer: View>: View {
    let title: String
    let caption: String
    var symbol: String? = "gearshape"
    var initials: String?
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        ZStack {
            FridayVaultBackdrop(motionEnabled: false).ignoresSafeArea()
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    if let initials {
                        FridayAvatar(initials: initials, size: 48, statusColor: nil)
                    } else {
                        ZStack {
                            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                                .fill(FridayVaultDesign.cyan.opacity(0.1))
                                .overlay(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous).stroke(FridayVaultDesign.cyan.opacity(0.35)))
                            Image(systemName: symbol ?? "gearshape")
                                .font(.system(size: 20, weight: .light))
                                .foregroundStyle(FridayVaultDesign.cyan)
                        }
                        .frame(width: 48, height: 48)
                    }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title)
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(FridayVaultDesign.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(caption.uppercased())
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(FridayVaultDesign.cyan)
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 18)
                .padding(.top, 22)
                .padding(.bottom, 14)
                Rectangle().fill(FridayVaultDesign.separator).frame(height: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) { content() }
                        .padding(18)
                }
                Rectangle().fill(FridayVaultDesign.separator).frame(height: 1)
                HStack(spacing: 10) { footer() }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
            }
        }
    }
}
