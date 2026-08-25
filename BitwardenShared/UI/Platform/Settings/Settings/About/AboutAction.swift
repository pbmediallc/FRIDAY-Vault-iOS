import BitwardenKit

// MARK: - AboutAction

/// Actions handled by the `AboutProcessor`.
///
enum AboutAction: Equatable {
    /// Clears the app review URL.
    case clearAppReviewURL

    /// The url has been opened so clear the value in the state.
    case clearURL

    /// An action for the Flight Recorder feature.
    case flightRecorder(FlightRecorderSettingsSectionAction)

    /// The corresponding source for this F.R.I.D.A.Y. Vault build was tapped.
    case fridaySourceTapped

    /// The help center button was tapped.
    case helpCenterTapped

    /// The learn about organizations button was tapped.
    case learnAboutOrganizationsTapped

    /// The rate the app button was tapped.
    case rateTheAppTapped

    /// The toast was shown or hidden.
    case toastShown(Toast?)

    /// The submit crash logs toggle value changed.
    case toggleSubmitCrashLogs(Bool)

    /// The verified Bitwarden upstream source and license button was tapped.
    case upstreamSourceTapped

    /// The web vault button was tapped.
    case webVaultTapped
}
