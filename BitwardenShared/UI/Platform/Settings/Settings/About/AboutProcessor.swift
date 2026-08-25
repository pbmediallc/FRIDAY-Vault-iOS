// MARK: - AboutProcessor

import BitwardenKit
import BitwardenResources
import Foundation

/// The processor used to manage state and handle actions for the `AboutView`.
///
final class AboutProcessor: StateProcessor<AboutState, AboutAction, AboutEffect> {
    // MARK: Types

    typealias Services = HasAppInfoService
        & HasConfigService
        & HasEnvironmentService
        & HasErrorReporter
        & HasFlightRecorder
        & HasPasteboardService

    /// The complete corresponding source for F.R.I.D.A.Y. Vault 1.0.1 (2026082502).
    private static let fridaySourceURL = URL(
        string: "https://github.com/pbmediallc/FRIDAY-Vault-iOS/tree/v1.0.1-2026082502",
    )

    /// The verified Bitwarden iOS upstream repository. Its root exposes the GPLv3 license.
    private static let upstreamSourceURL = URL(string: "https://github.com/bitwarden/ios")

    // MARK: Properties

    /// The coordinator used to manage navigation.
    private let coordinator: AnyCoordinator<SettingsRoute, SettingsEvent>

    /// The services used by this processor.
    private let services: Services

    // MARK: Initialization

    /// Initializes a new `AboutProcessor`.
    ///
    /// - Parameters:
    ///   - coordinator: The coordinator used to manage navigation.
    ///   - services: The services used by this processor.
    ///   - state: The initial state of the processor.
    init(
        coordinator: AnyCoordinator<SettingsRoute, SettingsEvent>,
        services: Services,
        state: AboutState,
    ) {
        self.coordinator = coordinator
        self.services = services

        // Set the initial value of the crash logs toggle.
        var state = state
        state.copyrightText = AboutState.legalNotice(
            upstreamCopyright: services.appInfoService.copyrightString,
        )
        state.isSubmitCrashLogsToggleOn = services.errorReporter.isEnabled
        state.version = services.appInfoService.versionString

        super.init(state: state)
    }

    // MARK: Methods

    override func perform(_ effect: AboutEffect) async {
        switch effect {
        case .copyVersionInfo:
            await copyVersionInfo()
        case let .flightRecorder(flightRecorderEffect):
            switch flightRecorderEffect {
            case let .toggleFlightRecorder(isOn):
                if isOn {
                    coordinator.navigate(to: .flightRecorder(.enableFlightRecorder))
                } else {
                    await services.flightRecorder.disableFlightRecorder()
                }
            }
        case .streamFlightRecorderLog:
            await streamFlightRecorderLog()
        }
    }

    override func receive(_ action: AboutAction) {
        switch action {
        case .clearAppReviewURL:
            state.appReviewUrl = nil
        case .clearURL:
            state.url = nil
        case let .flightRecorder(flightRecorderAction):
            switch flightRecorderAction {
            case .viewLogsTapped:
                coordinator.navigate(to: .flightRecorder(.flightRecorderLogs))
            }
        case .fridaySourceTapped:
            state.url = Self.fridaySourceURL
        case .helpCenterTapped:
            state.url = ExternalLinksConstants.helpAndFeedback
        case .learnAboutOrganizationsTapped:
            coordinator.showAlert(.learnAboutOrganizationsAlert {
                self.state.url = ExternalLinksConstants.aboutOrganizations
            })
        case .rateTheAppTapped:
            coordinator.showAlert(.appStoreAlert {
                self.state.appReviewUrl = ExternalLinksConstants.appReview
            })
        case let .toastShown(newValue):
            state.toast = newValue
        case let .toggleSubmitCrashLogs(isOn):
            state.isSubmitCrashLogsToggleOn = isOn
            services.errorReporter.isEnabled = isOn
        case .upstreamSourceTapped:
            state.url = Self.upstreamSourceURL
        case .webVaultTapped:
            coordinator.showAlert(.webVaultAlert {
                self.state.url = self.services.environmentService.webVaultURL
            })
        }
    }

    // MARK: - Private Methods

    /// Copies the app's version info to the pasteboard.
    private func copyVersionInfo() async {
        let appInfo = await services.appInfoService.appInfoWithoutCopyrightString
        services.pasteboardService.copy(
            """
            \(AboutState.productPublisherText)

            \(state.copyrightText)

            \(appInfo)
            """,
        )
        state.toast = Toast(title: Localizations.valueHasBeenCopied(Localizations.appInfo))
    }

    /// Streams the flight recorder's active log metadata.
    private func streamFlightRecorderLog() async {
        for await activeLog in await services.flightRecorder.activeLogPublisher().values {
            state.flightRecorderState.activeLog = activeLog
        }
    }
}
