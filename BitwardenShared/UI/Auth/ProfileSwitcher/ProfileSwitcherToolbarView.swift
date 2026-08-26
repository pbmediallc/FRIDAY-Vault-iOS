import BitwardenKit
import BitwardenResources
import SwiftUI

// MARK: - ProfileSwitcherToolbarView

/// A view that allows the user to view, select, and add profiles.
///
struct ProfileSwitcherToolbarView: View {
    /// The `Store` for this view.
    @ObservedObject var store: Store<ProfileSwitcherState, ProfileSwitcherAction, ProfileSwitcherEffect>

    var body: some View {
        profileSwitcherToolbarItem
    }

    /// The Toolbar item for the profile switcher view
    @ViewBuilder var profileSwitcherToolbarItem: some View {
        let iconSize: ProfileSwitcherIconSize = if #available(iOS 26, *) { .toolbar } else { .standard }
        // On iOS 26+, remove extra padding applied around the button, which allows the initials
        // font size to scale larger without increasing the overall width of the button.
        let horizontalPadding: CGFloat = if #available(iOS 26, *) { -4 } else { 0 }

        AsyncButton {
            await store.perform(.requestedProfileSwitcher(visible: !store.state.isVisible))
        } label: {
            profileSwitcherIcon(
                initials: store.state.showPlaceholderToolbarIcon
                    ? nil
                    : store.state.activeAccountProfile?.userInitials,
                size: iconSize,
            )
        }
        .backport.buttonStyleGlassProminent()
        .tint(FridayVaultDesign.elevated)
        .padding(.horizontal, horizontalPadding)
        .accessibilityIdentifier("CurrentActiveAccount")
        .accessibilityLabel(Localizations.account)
        .hidden(!store.state.showPlaceholderToolbarIcon && store.state.accounts.isEmpty)
    }
}

extension View {
    /// An icon for a profile switcher item.
    ///
    /// - Parameters:
    ///   - color: The color of the icon.
    ///   - initials: The initials for the icon.
    ///   - textColor: The text color for the icon.
    ///   - size: The size configuration for the icon.
    ///
    @ViewBuilder
    func profileSwitcherIcon(
        color _: Color? = SharedAsset.Colors.backgroundTertiary.swiftUIColor,
        initials: String?,
        textColor _: Color? = nil,
        size: ProfileSwitcherIconSize = .standard,
    ) -> some View {
        FridayVaultProfileAvatar(
            initials: initials,
            size: size.diameter,
            textStyle: size.textStyle,
            fontWeight: size.fontWeight,
        )
    }
}

// MARK: - ProfileSwitcherIconSize

/// Size configurations for profile switcher icons.
///
struct ProfileSwitcherIconSize {
    // MARK: Properties

    /// The font weight for the user's initials.
    let fontWeight: SwiftUI.Font.Weight

    /// The fixed visual diameter of the branded avatar.
    let diameter: CGFloat

    /// The text style for the user's initials.
    let textStyle: StyleGuideFont

}

extension ProfileSwitcherIconSize {
    /// The standard icon size for the profile switcher and toolbar pre-iOS 26.
    static let standard = ProfileSwitcherIconSize(
        fontWeight: .light,
        diameter: 30,
        textStyle: .caption2Monospaced,
    )

    /// A larger icon size for use as a toolbar icon on iOS 26+.
    static let toolbar = ProfileSwitcherIconSize(
        fontWeight: .light,
        diameter: 34,
        textStyle: .bodyMonospaced,
    )
}

// MARK: Previews

#if DEBUG
#Preview("Empty") {
    NavigationView {
        Spacer()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileSwitcherToolbarView(
                        store: Store(
                            processor: StateProcessor(
                                state: .empty(),
                            ),
                        ),
                    )
                }
            }
    }
}

#Preview("No Active") {
    NavigationView {
        Spacer()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileSwitcherToolbarView(
                        store: Store(
                            processor: StateProcessor(
                                state: .init(
                                    accounts: [.anneAccount],
                                    activeAccountId: nil,
                                    allowLockAndLogout: true,
                                    isVisible: false,
                                ),
                            ),
                        ),
                    )
                }
            }
    }
}

#Preview("Single Account") {
    NavigationView {
        Spacer()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileSwitcherToolbarView(
                        store: Store(
                            processor: StateProcessor(
                                state: .singleAccount,
                            ),
                        ),
                    )
                }
            }
    }
}

#Preview("Dual Account") {
    NavigationView {
        Spacer()
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    ProfileSwitcherToolbarView(
                        store: Store(
                            processor: StateProcessor(
                                state: ProfileSwitcherState(
                                    accounts: [
                                        .anneAccount,
                                        .fixture(color: .green, userId: "1", userInitials: "BB"),
                                    ],
                                    activeAccountId: "1",
                                    allowLockAndLogout: true,
                                    isVisible: false,
                                ),
                            ),
                        ),
                    )
                }
            }
    }
}
#endif
