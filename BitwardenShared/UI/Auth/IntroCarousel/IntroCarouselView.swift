import BitwardenKit
import BitwardenResources
import SwiftUI

// MARK: - IntroCarouselView

/// A view that allows the user to swipe through the intro carousel and then proceed to creating an
/// account or logging in.
///
struct IntroCarouselView: View {
    // MARK: Properties

    /// An environment variable for getting the vertical size class of the view.
    @Environment(\.verticalSizeClass) var verticalSizeClass

    /// The `Store` for this view.
    @ObservedObject var store: Store<IntroCarouselState, IntroCarouselAction, IntroCarouselEffect>

    // MARK: View

    var body: some View {
        ZStack {
            FridayVaultBackdrop(motionEnabled: true)

            VStack(spacing: 0) {
                TabView(selection: store.binding(
                    get: \.currentPageIndex,
                    send: IntroCarouselAction.currentPageIndexChanged,
                )) {
                    ForEachIndexed(store.state.pages) { index, page in
                        pageView(page)
                            .tag(index)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .always))
                .indexViewStyle(.page(backgroundDisplayMode: .always))
                .animation(.default, value: store.state.currentPageIndex)

                VStack(spacing: 12) {
                    AsyncButton(Localizations.createAccount) {
                        await store.perform(.createAccount)
                    }
                    .buttonStyle(.primary())

                    Button(Localizations.logIn) {
                        store.send(.logIn)
                    }
                    .buttonStyle(.secondary())
                }
                .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard)
                        .fill(FridayVaultDesign.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: FridayVaultDesign.cornerCard)
                                .stroke(FridayVaultDesign.edge.opacity(0.85), lineWidth: 1),
                        ),
                )
                .shadow(color: FridayVaultDesign.cyan.opacity(0.12), radius: 18, y: 8)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(FridayVaultDesign.text)
        .multilineTextAlignment(.center)
    }

    /// A dynamic stack view that lays out content vertically when in a regular vertical size class
    /// and horizontally for the compact vertical size class.
    @ViewBuilder
    private func dynamicStackView(
        minHeight: CGFloat,
        @ViewBuilder imageContent: () -> some View,
        @ViewBuilder textContent: () -> some View,
    ) -> some View {
        Group {
            if verticalSizeClass == .regular {
                VStack(spacing: 80) {
                    imageContent()
                    textContent()
                }
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, minHeight: minHeight)
            } else {
                HStack(alignment: .top, spacing: 40) {
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)
                        imageContent()
                            .padding(.leading, 36)
                            .padding(.vertical, 16)
                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: minHeight)

                    textContent()
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity, minHeight: minHeight)
                }
            }
        }
        .scrollView(
            addVerticalPadding: false,
            backgroundColor: .clear,
        )
    }

    /// A view that displays a carousel page.
    @ViewBuilder
    private func pageView(_ page: IntroCarouselState.CarouselPage) -> some View {
        GeometryReader { reader in
            dynamicStackView(minHeight: reader.size.height) {
                ZStack(alignment: .bottomTrailing) {
                    FridayVaultShieldMark(
                        size: verticalSizeClass == .regular ? 164 : 124,
                        motionEnabled: true,
                    )

                    Image(systemName: page.symbol)
                        // SF Symbols require a system font for precise symbol sizing on iOS 15.
                        // swiftlint:disable:next style_guide_font
                        .font(.system(size: verticalSizeClass == .regular ? 25 : 20, weight: .semibold))
                        .foregroundStyle(FridayVaultDesign.electric)
                        .frame(
                            width: verticalSizeClass == .regular ? 50 : 42,
                            height: verticalSizeClass == .regular ? 50 : 42,
                        )
                        .background(
                            Circle()
                                .fill(FridayVaultDesign.elevated)
                                .overlay(
                                    Circle()
                                        .stroke(FridayVaultDesign.cyan.opacity(0.7), lineWidth: 1),
                                ),
                        )
                        .shadow(color: FridayVaultDesign.cyan.opacity(0.45), radius: 8)
                        .accessibilityHidden(true)
                }
            } textContent: {
                VStack(spacing: 14) {
                    Text("F.R.I.D.A.Y. VAULT")
                        .tracking(1.5)
                        .styleGuide(.caption1, weight: .semibold)
                        .foregroundStyle(FridayVaultDesign.electric)

                    Text(page.title)
                        .styleGuide(.title, weight: .bold)
                        .foregroundStyle(FridayVaultDesign.text)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(page.message)
                        .styleGuide(.title3)
                        .foregroundStyle(FridayVaultDesign.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 8)
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("Carousel") {
    IntroCarouselView(store: Store(processor: StateProcessor(state: IntroCarouselState())))
}

@available(iOS 17, *)
#Preview("Carousel Landscape", traits: .landscapeRight) {
    IntroCarouselView(store: Store(processor: StateProcessor(state: IntroCarouselState())))
}
#endif
