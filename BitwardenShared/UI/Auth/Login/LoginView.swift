import BitwardenKit
import BitwardenResources
import SwiftUI

// MARK: - LoginView

/// A view that allows the user to input their master password to complete the
/// login flow, or allows the user to navigate to separate views for alternate
/// forms of login.
///
struct LoginView: View {
    // MARK: Properties

    /// The `Store` for this view.
    @ObservedObject var store: Store<LoginState, LoginAction, LoginEffect>

    var body: some View {
        ZStack {
            FridayVaultBackdrop(motionEnabled: false)

            VStack(spacing: 24) {
                FridayVaultBrandHeader(
                    subtitle: Localizations.logIn,
                    status: Localizations.accountLocked,
                    statusSymbol: "lock.shield.fill",
                    statusColor: FridayVaultDesign.cyan,
                    motionEnabled: false,
                )

                VStack(spacing: 24) {
                    textField

                    loginButtons

                    loggedInAs
                }
                .padding(20)
                .background(FridayVaultDesign.panel.opacity(0.94))
                .clipShape(RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard, style: .continuous)
                        .stroke(FridayVaultDesign.edge, lineWidth: 1)
                }
                .disabled(store.state.isLoggingIn)
            }
            .scrollView(backgroundColor: .clear)
        }
        .navigationTitle(Localizations.bitwarden)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            optionsToolbarMenu {
                Button(Localizations.getMasterPasswordwordHint) {
                    store.send(.getMasterPasswordHintPressed)
                }
            }
        }
        .task {
            await store.perform(.appeared)
        }
    }

    /// The text field along with the master password hint button.
    @ViewBuilder var textField: some View {
        VStack(alignment: .leading, spacing: 8) {
            BitwardenTextField(
                title: Localizations.masterPassword,
                text: store.binding(
                    get: \.masterPassword,
                    send: LoginAction.masterPasswordChanged,
                ),
                accessibilityIdentifier: "LoginMasterPasswordEntry",
                passwordVisibilityAccessibilityId: "PasswordVisibilityToggle",
                isPasswordAutoFocused: true,
                isPasswordVisible: store.binding(
                    get: \.isMasterPasswordRevealed,
                    send: LoginAction.revealMasterPasswordFieldPressed,
                ),
                footerContent: {
                    Button(Localizations.getMasterPasswordwordHint) {
                        store.send(.getMasterPasswordHintPressed)
                    }
                    .buttonStyle(.bitwardenBorderless)
                    .padding(.vertical, 14)
                    .accessibilityIdentifier("GetMasterPasswordHintLabel")
                },
            )
            .textFieldConfiguration(.password)
            .submitLabel(.go)
            .onSubmit {
                guard !store.state.isLoggingIn else { return }
                Task {
                    await store.perform(.loginWithMasterPasswordPressed)
                }
            }
        }
    }

    /// The set of login option buttons.
    @ViewBuilder var loginButtons: some View {
        VStack(alignment: .center, spacing: 12) {
            AsyncButton(Localizations.logInWithMasterPassword) {
                await store.perform(.loginWithMasterPasswordPressed)
            }
            .accessibilityIdentifier("LogInWithMasterPasswordButton")
            .buttonStyle(.primary())

            if store.state.isLoginWithDeviceVisible {
                Button {
                    store.send(.loginWithDevicePressed)
                } label: {
                    HStack(spacing: 8) {
                        Image(decorative: SharedAsset.Icons.mobile16)
                            .imageStyle(.accessoryIcon16(scaleWithFont: true))
                        Text(Localizations.logInWithDevice)
                    }
                }
                .accessibilityIdentifier("LogInWithAnotherDeviceButton")
                .buttonStyle(.secondary())
            }

            Button {
                store.send(.enterpriseSingleSignOnPressed)
            } label: {
                HStack(spacing: 8) {
                    Image(decorative: SharedAsset.Icons.provider16)
                        .imageStyle(.accessoryIcon16(scaleWithFont: true))
                    Text(Localizations.logInSso)
                }
            }
            .accessibilityIdentifier("LogInWithSsoButton")
            .buttonStyle(.secondary())
        }
    }

    /// The "logged in as..." text along with the not you button.
    @ViewBuilder var loggedInAs: some View {
        VStack(alignment: .center, spacing: 2) {
            Text(Localizations.loggedInAsOn(
                store.state.username,
                store.state.serverURLString,
            ))
            .accessibilityIdentifier("LoggingInAsLabel")
            .foregroundColor(SharedAsset.Colors.textSecondary.swiftUIColor)
            .multilineTextAlignment(.center)

            Button(Localizations.notYou) {
                store.send(.notYouPressed)
            }
            .accessibilityIdentifier("NotYouLabel")
            .foregroundColor(SharedAsset.Colors.textInteraction.swiftUIColor)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .styleGuide(.footnote)
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Empty") {
    NavigationView {
        LoginView(
            store: Store(
                processor: StateProcessor(
                    state: LoginState(),
                ),
            ),
        )
    }
}

#Preview("With Device") {
    NavigationView {
        LoginView(
            store: Store(
                processor: StateProcessor(
                    state: LoginState(
                        isLoginWithDeviceVisible: true,
                    ),
                ),
            ),
        )
    }
}
#endif
