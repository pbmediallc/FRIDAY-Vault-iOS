import BitwardenResources
import Foundation

// MARK: - IntroCarouselState

/// An object that defines the current state of a `IntroCarouselView`.
///
struct IntroCarouselState: Equatable {
    // MARK: Types

    /// A model representing the data to display on a single page in the carousel.
    ///
    struct CarouselPage: Equatable, Identifiable {
        // MARK:

        /// A unique identifier of the page.
        let id: String = UUID().uuidString

        /// A message to display on the page.
        let message: String

        /// The system symbol displayed in the page's status badge.
        let symbol: String

        /// A title to display on the page.
        let title: String
    }

    // MARK: Properties

    /// The index of the currently visible page in the carousel.
    var currentPageIndex = 0

    /// The list of scrollable pages displayed in the carousel.
    let pages: [CarouselPage] = [
        CarouselPage(
            message: Localizations.introCarouselPage1Message,
            symbol: "lock.shield.fill",
            title: Localizations.introCarouselPage1Title,
        ),

        CarouselPage(
            message: Localizations.introCarouselPage2Message,
            symbol: "faceid",
            title: Localizations.introCarouselPage2Title,
        ),

        CarouselPage(
            message: Localizations.introCarouselPage3Message,
            symbol: "key.fill",
            title: Localizations.introCarouselPage3Title,
        ),

        CarouselPage(
            message: Localizations.introCarouselPage4Message,
            symbol: "arrow.triangle.2.circlepath",
            title: Localizations.introCarouselPage4Title,
        ),
    ]
}
