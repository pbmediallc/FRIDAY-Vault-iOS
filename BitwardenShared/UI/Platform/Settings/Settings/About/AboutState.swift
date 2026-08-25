import BitwardenKit
import BitwardenResources
import Foundation

// MARK: - AboutState

/// An object that defines the current state of the `AboutView`.
///
struct AboutState {
    // MARK: Types

    /// The F.R.I.D.A.Y. Vault product name shown in About and copied diagnostics.
    static let productName = "F.R.I.D.A.Y. VAULT"

    /// The publisher shown in About and copied diagnostics.
    static let publisherName = "PB Media"

    /// The product and publisher identity shown in copied diagnostics.
    static let productPublisherText = "\(productName) · \(publisherName)"

    /// The title for the complete corresponding source of this distributed build.
    static let fridaySourceTitle = "F.R.I.D.A.Y. Vault 1.0.1 (2026082501) · Source · GNU GPLv3"

    /// The title for the verified Bitwarden upstream source and license link.
    static let upstreamSourceTitle = "Bitwarden iOS · Upstream · GNU GPLv3"

    /// The brand-neutral web vault destination shown in About.
    static let webVaultTitle = "F.R.I.D.A.Y. Vault · Web"

    // MARK: Properties

    /// The URL for Bitwarden's app review page in the app store.
    var appReviewUrl: URL?

    /// The copyright text.
    var copyrightText = ""

    /// The state for the Flight Recorder feature.
    var flightRecorderState = FlightRecorderSettingsSectionState()

    /// Whether the submit crash logs toggle is on.
    var isSubmitCrashLogsToggleOn: Bool = false

    /// A toast message to show in the view.
    var toast: Toast?

    /// The url to open in the device's web browser.
    var url: URL?

    /// The version of the app.
    var version = ""

    // MARK: Methods

    /// Returns a label that makes it explicit that a destination belongs to Bitwarden upstream.
    static func upstreamLinkTitle(_ title: String) -> String {
        "\(title) · Bitwarden Upstream"
    }

    /// Returns the legal notice shown for this modified upstream application.
    static func legalNotice(upstreamCopyright: String) -> String {
        [
            "Modified from Bitwarden iOS. You may redistribute it under GNU GPLv3; it comes without warranty.",
            "F.R.I.D.A.Y. Vault is not affiliated with or endorsed by Bitwarden, Inc.",
            "Upstream: \(upstreamCopyright)",
        ]
        .joined(separator: "\n")
    }
}
